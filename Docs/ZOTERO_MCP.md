# Operational Guide: First-party Zotero MCP

This non-normative operator guide covers the installed Scholium CLI.
[Specification §15](Specification/05-integrations-onboarding-and-boundaries.md#15-zotero-integration)
owns product and research boundaries; `scholium help zotero` owns exact syntax.

Scholium's built-in Zotero reader and external-agent MCP transport are separate.
The app reader remains bounded and read-only. The MCP service is
`scholium zotero mcp serve`; opening Zotero does not start it.

In Chat Settings → Skills and Tools, **Set Up Zotero…** opens the existing
configuration editor with the bundled CLI and `zotero mcp serve --read-only`.
Save **Enabled** there; the selected Codex configuration owns that choice across
reconnects. This mode publishes read tools and refuses imports even if a caller
names an unadvertised import tool. Shared settings retain their ordinary shared
change confirmation. **Check Connection** reports local API availability
separately from the configured MCP server's connection state. It reads no paper
into Chat. A custom same-name connection is never silently replaced.

## Install and verify the CLI

Open **Settings → Integrations → Agents & Chat** and choose a setup command for
the external Agent. The page reports the installed Scholium CLI and its exact
path before copying the command.
The official installer places the version-matched executable and resource
bundle under `~/.local/bin` without editing a shell profile. After installation,
the standalone CLI can check or install a newer verified release explicitly:

```sh
scholium update --check
scholium update
```

Confirm that the external Agent can see the installed command:

```sh
scholium version --format json
scholium doctor --format json
scholium help zotero
```

From a source checkout, use the maintained installer rather than copying the
executable without its adjacent resource bundle:

```sh
Tools/Scripts/install-cli.sh
export PATH="$PWD/.build/cli-prefix/bin:$PATH"
```

## Configure an MCP client

Print configuration for the installed version:

```sh
scholium zotero mcp config --format json
```

The current default shape is:

```json
{
  "mcpServers": {
    "zotero": {
      "command": "scholium",
      "args": ["zotero", "mcp", "serve"]
    }
  }
}
```

If the Agent does not inherit `~/.local/bin`, apply the PATH command shown by
Scholium or use the verified absolute executable path in that Agent's MCP
configuration. Keep the adjacent `Scholium_ScholiumCore.bundle` resource bundle
with the executable.

Enable Zotero's local API in **Zotero Settings → Advanced → Allow other
applications on this computer to communicate with Zotero**.

## Check availability without research access

```sh
scholium zotero mcp status
```

This locates the command without launching it. Adding `--probe` performs only
the MCP initialize lifecycle, then terminates. It does not list tools, inspect
a library, request attachments, or import records.

An MCP initialize response proves only that the stdio service exists.
`zotero_status` separately reports Zotero Desktop's local API and Connector
readiness.

## Current tool surface

- `zotero_status`: local API and Connector readiness;
- `zotero_search`: bounded metadata search across local user and group
  libraries;
- `zotero_item`: exact item inspection and optional bounded attachment
  pointers;
- `zotero_list_annotations`: paginated annotation pointers for an exact
  library/PDF attachment, with a listing fingerprint required on continuation;
- `zotero_read_annotation`: one selected annotation, optionally pinned to its
  pointer fingerprint, with text, comment and physical/printed page kept separate;
- `zotero_read_original`: an exact local attachment's bounded text slice or
  selected PDF page/image, retaining the original-file fingerprint;
- `zotero_selected_target`: the currently selected editable library or
  collection, without enumerating the complete tree; and
- `zotero_import_bibtex` and `zotero_import_ris`: guarded Connector imports.

Retrieval uses Zotero Desktop's localhost interfaces, never its live database.
Item, PDF-page and annotation locators share validated `zotero://` URLs. They
can be opened from Chat replies/Sources without implying that material was read.
Annotation lists are bounded to 1,000 records/4 MiB and 50 pointers per page;
changed or oversized snapshots fail. Annotation reads verify the attachment and
parent relationship, but do not read PDF bytes or corroborate the selected text.
Original reads accept no arbitrary path or URL. The API resolves the selected
attachment; file type/name, metadata, path and exact bytes are revalidated under
a 20 MiB limit. Symlinked components, redirects, unavailable/locked originals,
changed versions and unsupported formats fail without index substitution.
Text is capped at 64 KiB; nonzero offsets require the original fingerprint.
PDFs require one physical page. Image mode returns a bounded native PNG;
it does not perform OCR. No original is automatically staged or persisted.
The supported locator forms follow Zotero's
[protocol handler](https://github.com/zotero/zotero/blob/main/chrome/content/zotero/ZoteroProtocolHandler.mjs).
Its [local API implementation](https://github.com/zotero/zotero/blob/main/chrome/content/zotero/xpcom/server/server_localAPI.js)
distinguishes item/annotation JSON, indexed full text and local file URLs.
Imports follow §15's exact-request, dry-run, confirmation, unchanged-destination,
and readback boundary. Metadata establishes bibliographic identity only. When
an Analysis Run carries the matching Zotero binding, the external Agent may
use this transport and its returned attachment pointer to retrieve the paper
data it needs; Scholium does not automatically fetch or persist original-file
content. Source analysis and citation formatting remain separate scholarly
work. The Agent states material access or extraction limits when they constrain
what the academic result can support; Scholium retains no reading history.
