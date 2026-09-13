# Operational Guide: First-party Zotero MCP

This non-normative guide describes the App-bundled read-only connection helper.
[Specification §15](Specification/05-integrations-onboarding-and-boundaries.md#15-zotero-integration)
owns the supported scope.

In Settings → Integrations → Agents & Chat → Skills and Tools, **Set Up Zotero…**
opens the runtime configuration editor with the bundled helper and
`zotero mcp serve --read-only`. Save **Enabled** there. The runtime owns this
choice; custom or disabled connections are never silently replaced.

Enable Zotero's local API in Zotero Settings → Advanced → Allow other
applications on this computer to communicate with Zotero. **Check Connection**
reports that API's availability separately from the MCP server connection.
Checking readiness neither reads a paper nor supplies material to Chat.

External hosts may configure the same installed App helper with those arguments.
Use its exact `Contents/Helpers/ScholiumAgentHelper` path. Updating the App in
place updates the helper; moving the App requires updating the host's path.
There is no standalone installation or updater.

The service exposes seven read tools: `zotero_status`, `zotero_search`,
`zotero_item`, `zotero_list_annotations`, `zotero_read_annotation`,
`zotero_read_original`, and `zotero_selected_target`. Import calls are rejected.
Tool schemas define exact inputs and bounds. Reads use local interfaces, never
Zotero's live database. Metadata, annotations, extracted text and original-page
images remain distinct representations with their reported scope and identity.

If the App helper is missing, reinstall the App. If Zotero is unavailable,
restore its local API connection; ordinary Scholium Note work remains available.
An MCP connection is not proof that a source was read.
