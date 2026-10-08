#!/usr/bin/env python3
"""Guard the closed MCP catalog and exercise the isolated distributed helper."""
from collections import Counter
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import uuid


# Pin wire identities independently of the implementation under test. These are
# the external research surface and the conversation-token-only Chat extension.
RESEARCH_TOOLS = {
    "workspaceStatus": "scholium_workspace_status",
    "browse": "scholium_browse",
    "search": "scholium_search",
    "readNote": "scholium_read_note",
    "showNote": "scholium_show_note",
    "listAttachments": "scholium_list_attachments",
    "readAttachment": "scholium_read_attachment",
    "listLinks": "scholium_list_links",
    "createNote": "scholium_create_note",
    "updateNote": "scholium_update_note",
    "moveNote": "scholium_move_note",
    "previewMove": "scholium_preview_move",
    "listChanges": "scholium_list_changes",
    "readChange": "scholium_read_change",
    "undoChange": "scholium_undo_change",
    "trashNote": "scholium_trash_note",
}
CHAT_CONTROLS = {
    "capabilities": "scholium_capabilities",
    "configureSkill": "scholium_configure_skill",
    "configureTool": "scholium_configure_tool",
    "configureChat": "scholium_configure_chat",
    "observeCurrentState": "scholium_observe_current_state",
}


def require_catalog(actual, expected, label):
    actual, expected = Counter(actual), Counter(expected)
    if actual != expected:
        raise AssertionError(
            f"MCP surface guard failed ({label}): "
            f"missing {list((expected - actual).elements())}; "
            f"unexpected {list((actual - expected).elements())}")


def check_source_surface(source):
    # This deliberately accepts only the current literal enum and closed switch.
    # A structural rewrite must update this guard; unparsed cases cannot pass.
    enums = re.findall(
        r"^public enum ScholiumMCPToolName: String, Codable, CaseIterable, Sendable \{\n(.*?)^\}",
        source, re.MULTILINE | re.DOTALL)
    if len(enums) != 1:
        raise AssertionError("MCP surface guard failed: expected one closed tool enum")
    body = re.sub(r"(?m)^\s*//[^\n]*", "", enums[0])
    parts = body.split("public var isChatControl: Bool")
    if len(parts) != 2:
        raise AssertionError("MCP surface guard failed: unrecognized closed enum/classification")
    cases = []
    for line in parts[0].splitlines():
        if not line.strip():
            continue
        case = re.fullmatch(r'\s*case\s+(\w+)\s*=\s*"(\w+)"\s*', line)
        if case is None:
            raise AssertionError("MCP surface guard failed: unrecognized closed enum/classification")
        cases.append(case.groups())
    shape = re.fullmatch(
        r"\s*\{\s*switch self\s*\{\s*"
        r"case\s+(?P<chat>\.\w+(?:\s*,\s*\.\w+)*)\s*:\s*true\s*"
        r"default\s*:\s*false\s*\}\s*\}\s*", parts[1])
    if shape is None:
        raise AssertionError("MCP surface guard failed: unrecognized closed enum/classification")
    require_catalog(cases, {**RESEARCH_TOOLS, **CHAT_CONTROLS}.items(), "wire identities")
    require_catalog(re.findall(r"\.(\w+)", shape["chat"]), CHAT_CONTROLS.keys(), "Chat-only classification")


def check(executable, root):
    environment = {"PATH": "/usr/bin:/bin", "SCHOLIUM_APP_BRIDGE_CONTAINER": str(root / "bridge")}
    def call(arguments, messages):
        result = subprocess.run([str(executable), *arguments],
            input="".join(json.dumps(message) + "\n" for message in messages),
            text=True, capture_output=True, timeout=15, cwd=root, env=environment)
        assert result.returncode == 0, result.stderr
        return [json.loads(line) for line in result.stdout.splitlines() if line.strip()]

    listing = {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}
    initialize = {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": {"protocolVersion": "2025-11-25", "capabilities": {},
                             "clientInfo": {"name": "helper-smoke", "version": "1"}}}
    status = {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
              "params": {"name": "scholium_workspace_status", "arguments": {}}}
    chat_calls = [{"jsonrpc": "2.0", "id": index, "method": "tools/call",
                   "params": {"name": name, "arguments": {}}}
                  for index, name in enumerate(CHAT_CONTROLS.values(), start=4)]
    external = call(["mcp", "serve"], [initialize, listing, status, *chat_calls])
    assert external[0]["result"]["serverInfo"]
    require_catalog((tool["name"] for tool in external[1]["result"]["tools"]),
                    RESEARCH_TOOLS.values(), "external helper")
    assert all(tool["outputSchema"]["type"] == "object" for tool in external[1]["result"]["tools"])
    assert external[2].get("error") or external[2]["result"].get("isError") is True
    assert len(external) == 3 + len(chat_calls)
    for response, request in zip(external[3:], chat_calls):
        assert response["id"] == request["id"]
        assert response["result"]["isError"] is True
        assert response["result"]["structuredContent"]["code"] == "invalid_request"
    scoped = call(["mcp", "serve", "--conversation-token", str(uuid.uuid4())], [listing])
    require_catalog((tool["name"] for tool in scoped[0]["result"]["tools"]),
                    [*RESEARCH_TOOLS.values(), *CHAT_CONTROLS.values()], "Chat helper")
    assert all(tool["outputSchema"]["type"] == "object" for tool in scoped[0]["result"]["tools"])
    zotero = call(["zotero", "mcp", "serve"], [initialize, listing])
    assert zotero[0]["result"]["serverInfo"]["name"] == "scholium-zotero"
    zotero_names = {tool["name"] for tool in zotero[1]["result"]["tools"]}
    assert {"zotero_search", "zotero_fulltext", "zotero_read_original_page", "zotero_read_original_file"} <= zotero_names
    assert "zotero_update_item" in zotero_names
    assert "zotero_import_bibtex" not in zotero_names and "zotero_import_ris" not in zotero_names
    read_only = call(["zotero", "mcp", "serve", "--read-only"], [listing])
    read_only_names = {tool["name"] for tool in read_only[0]["result"]["tools"]}
    assert "zotero_update_item" not in read_only_names
    for args in [["version"], ["update"], ["search", "test"],
                 ["zotero", "mcp", "serve", "--unsupported"],
                 ["mcp", "serve", "--conversation-token", "invalid"]]:
        result = subprocess.run([str(executable), *args], capture_output=True, timeout=15,
                                cwd=root, env=environment)
        assert result.returncode != 0 and not result.stdout
    assert not (root / "Workspace").exists()
    print("Bundled helper: Scholium isolation, independent Zotero read/write surface, absent-App refusal and closed entry points passed")


if __name__ == "__main__":
    if sys.argv[1:] == ["--surface-only"]:
        contracts = Path(__file__).resolve().parents[2] / "ScholiumContracts/ScholiumMCPContracts.swift"
        try:
            check_source_surface(contracts.read_text(encoding="utf-8"))
        except (OSError, AssertionError) as error:
            sys.exit(str(error))
        print("MCP surface: exact 16 external tools and five Chat-only controls passed")
        sys.exit(0)
    executable = Path(sys.argv[1]).resolve(strict=True)
    scratch = Path(__file__).resolve().parents[2] / ".build"
    with tempfile.TemporaryDirectory(prefix="helper-smoke-", dir=scratch) as folder:
        check(executable, Path(folder))
