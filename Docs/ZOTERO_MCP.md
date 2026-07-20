# First-party Zotero MCP transport

Scholium's built-in Zotero interface and its external-agent MCP transport are
separate components. The app interface remains bounded and read-only. The MCP
service is the first-party `scholium zotero mcp serve` CLI command.

Opening Zotero does not start MCP. An MCP `initialize` handshake proves only
that the stdio service exists; `zotero_status` separately reports local API and
Connector readiness.

Neither path accesses `zotero.sqlite`; retrieval uses Zotero Desktop's API at
`127.0.0.1:23119`. The app neither enumerates attachments nor writes Zotero.
MCP returns bounded attachment pointers only on explicit request.

## Install the Scholium CLI

The public Beta bundles its exact version-matched **Scholium CLI** helper; it
has no separate CLI asset. Open **Settings → Research
Guidance → Skills → Advanced → Scholium CLI** and choose **Install**. Scholium
installs the executable and its required resource bundle under
`~/.local/bin`, verifies the installation, reports whether that directory is
discoverable through `PATH`, and offers a PATH setup command without editing a
shell profile.

Confirm the external agent sees the installed executable before configuring
MCP:

```sh
scholium version --format json
scholium doctor --format json
scholium help zotero
```

For development from a source checkout, use the maintained installer rather
than copying a bare executable without its resource bundle:

```sh
Tools/Scripts/install-cli.sh
```

Print a pasteable MCP client configuration:

```sh
scholium zotero mcp config --format json
```

The configuration is:

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

If the external agent does not inherit `~/.local/bin`, apply the PATH command
shown by Scholium or replace `scholium` in that agent's MCP configuration with
the verified absolute executable path. Do not move the executable without its
adjacent `Scholium_ScholiumCore.bundle` resource bundle.

`scholium zotero mcp status` locates the command without launching it. With
`--probe`, it performs only `initialize` and `notifications/initialized`, then
terminates; it does not list tools, inspect a library, request attachments, or
import records.

Enable Zotero's local API in Zotero Settings → Advanced → **Allow other
applications on this computer to communicate with Zotero**.

## Exposed capabilities

- `zotero_status`: local API and Connector readiness;
- `zotero_search`: bounded metadata search across the local user and group
  libraries;
- `zotero_item`: exact item inspection, with optional bounded attachment
  pointers;
- `zotero_selected_target`: only the currently selected library or collection,
  without returning the complete collection tree or tags;
- `zotero_import_bibtex` and `zotero_import_ris`: guarded Connector imports.

Search and item inspection preserve library identity. If an item key or
destination is ambiguous, the transport refuses to choose silently.

## Guarded import boundary

Retrieval is the default. A real BibTeX or RIS import requires all of the
following:

1. an explicit current-task request for the exact supplied record;
2. an editable library or collection selected by the researcher in Zotero;
3. a successful `dry_run=true` call for the unchanged import text;
4. the unexpired one-shot token returned by that preview;
5. a real call with `dry_run=false` and `confirm=true` while the selected target
   remains unchanged; and
6. read-back of every returned item through Zotero's read-only local API.

The process-local ten-minute token binds operation, exact content hash, record
count, and destination. Target/content changes, replay, missing confirmation,
ambiguity, or failed read-back fail explicitly. If Zotero accepts a write but
verification fails, report possible completion without claiming verified
success.

Imports use Zotero's localhost Connector; Scholium does not request or store a
Zotero Web API key. The service never changes Zotero preferences, starts Zotero
silently, selects a destination, opens an attachment, or reads the live
database.

Metadata establishes identity only, never evidence for a quotation, locator,
claim, concept, argument, or interpretation. The protected contract is
`ScholiumCore/Resources/Skills/Scholium System Skills/scholium-zotero-integration/references/mcp-contract.md`.
