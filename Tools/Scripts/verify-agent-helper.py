#!/usr/bin/env python3
"""Exercise the distributed helper without opening an App or research vault."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid


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
    external = call(["mcp", "serve"], [initialize, listing, status])
    assert external[0]["result"]["serverInfo"]
    assert len(external[1]["result"]["tools"]) == 16
    assert external[2].get("error") or external[2]["result"].get("isError") is True
    scoped = call(["mcp", "serve", "--conversation-token", str(uuid.uuid4())], [listing])
    assert len(scoped[0]["result"]["tools"]) == 20
    zotero = call(["zotero", "mcp", "serve"], [initialize, listing])
    assert zotero[0]["result"]["serverInfo"]["name"] == "scholium-zotero"
    zotero_names = {tool["name"] for tool in zotero[1]["result"]["tools"]}
    assert {"zotero_search", "zotero_fulltext", "zotero_import_bibtex", "zotero_update_item"} <= zotero_names
    read_only = call(["zotero", "mcp", "serve", "--read-only"], [listing])
    read_only_names = {tool["name"] for tool in read_only[0]["result"]["tools"]}
    assert "zotero_import_bibtex" not in read_only_names and "zotero_update_item" not in read_only_names
    for args in [["version"], ["update"], ["search", "test"],
                 ["zotero", "mcp", "serve", "--unsupported"],
                 ["mcp", "serve", "--conversation-token", "invalid"]]:
        result = subprocess.run([str(executable), *args], capture_output=True, timeout=15,
                                cwd=root, env=environment)
        assert result.returncode != 0 and not result.stdout
    assert not (root / "Workspace").exists()
    print("Bundled helper: Scholium isolation, independent Zotero read/write surface, absent-App refusal and closed entry points passed")


if __name__ == "__main__":
    executable = Path(sys.argv[1]).resolve(strict=True)
    scratch = Path(__file__).resolve().parents[2] / ".build"
    with tempfile.TemporaryDirectory(prefix="helper-smoke-", dir=scratch) as folder:
        check(executable, Path(folder))
