# Operational Guide: First-party Zotero MCP

This is a non-normative operator guide for the currently installed Scholium
CLI. [Specification §15](Specification/05-integrations-onboarding-and-boundaries.md#15-zotero-integration)
owns product behavior and research boundaries; [Implementation Architecture](IMPLEMENTATION_ARCHITECTURE.md)
owns code structure; `scholium help zotero` owns exact syntax for the installed
version. If this guide and installed help differ, follow installed help and
correct this guide.

Scholium's built-in Zotero reader and external-agent MCP transport are separate.
The app reader remains bounded and read-only. The MCP service is
`scholium zotero mcp serve`; opening Zotero does not start it.

## Install and verify the CLI

Open **Settings → Research Guidance → Sources & Integrations → Scholium CLI**
and choose **Install**. Scholium installs the version-matched executable and
resource bundle under `~/.local/bin`, verifies them, reports whether that
directory is visible through `PATH`, and offers a setup command without editing
a shell profile.

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
- `zotero_selected_target`: the currently selected editable library or
  collection, without enumerating the complete tree; and
- `zotero_import_bibtex` and `zotero_import_ris`: guarded Connector imports.

Retrieval uses Zotero Desktop's localhost interfaces and never the live
`zotero.sqlite` database. A real import requires an explicit request for the
exact record and destination, an unchanged successful dry run, its unexpired
one-shot token, explicit confirmation, and readback. Ambiguity, target change,
content change, replay, or unverifiable completion fails explicitly.

Metadata establishes bibliographic identity only. It is not evidence for a
quotation, locator, claim, concept, argument, or interpretation. Source
analysis and citation formatting remain separately requested scholarly work.
