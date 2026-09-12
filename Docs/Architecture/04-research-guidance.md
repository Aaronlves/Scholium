# Architecture: Settings integrations

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Agent
Integration, Zotero configuration, and Settings ownership.

The Settings **Integrations** pane is navigation, not an Agent runtime. It
contains **Agents & Chat** and **Zotero**; those children preserve their
separate feature owners, storage boundaries and connection semantics.

## Agents & Chat

`AgentIntegrationSettingsView` receives delivery-neutral availability values
from `WorkspaceSettingsModel`. Application resolves the installed CLI and
release-bundled Core Protocol locations. The App reports its own availability;
the authenticated bridge status comes from the live App bridge owner.

Host setup actions write one generated command through the shared native
pasteboard boundary. The command contains the verified absolute CLI path and
`mcp serve`; Codex and Claude labels and scope are presentation choices only.
Scholium does not execute the command, edit host configuration, install a Skill,
or record a configuration-success claim.

The Core Protocol reveal route is a Finder action over a release resource.
Researcher-owned Skills remain in the external host and have no Scholium
registration, parser, store, editor, or recovery state.

## Zotero

Zotero remains an optional integration with one Application-owned capability.
Its settings, exact library/item identity, attachment containment, and
revision-checked Metadata plans remain separate from MCP Agent collaboration.
The optional first-party Zotero MCP transport has its own operator guide and
does not expand Scholium's knowledge-base MCP surface. `ZoteroMCPAccess` binds
one CLI session to read-only or guarded-import delivery. Core uses one predicate
for discovery and dispatch, so hidden import tools cannot execute in read-only
mode. Application metadata and MCP share Core's bounded URLSession client and
redirect policy. Foundation request injection stays inside Application composition;
delivery and boundary tests never construct Core services. The client cancels oversized or
cancelled responses. `ZoteroMCPAnnotations` uses that server's request factory
and API validation for exact PDF/annotation reads, paginated snapshot pointers,
record fingerprints and attachment revalidation; it owns no material store.
`ZoteroMCPOriginals` resolves only an exact attachment's API file URL, checks its
metadata and supported type, then reuses `VaultAttachmentStore` bounded,
descriptor-relative coordinated reads. It rechecks metadata, URL and bytes
before passing the snapshot to the same Core `AgentAttachmentContentReader`
used by Note attachments. Only selected text/page/image coverage enters the
tool response; originals have no second archive or writable projection.
`ZoteroReference` owns library/item/PDF-page/annotation URL validation and
serialization. Binding presentation, MCP results, Chat links/Sources and native
external navigation use it; a locator does not create source-read evidence.

## Settings authority

Workspace, Document, Metadata and Notifications settings retain their existing
owners; the Integrations and Interaction panes only compose those owners.
`WorkspaceSettingsModel` presents immutable snapshots and delegates writes to
Application capabilities. Portable Triptych settings contain Metadata
definitions, About order, Attention timing, and other declared portable state.
Unsupported pre-production state remains subject to the specification's
non-migration and byte-preservation boundaries; architecture adds no compatibility
policy.

Settings search indexes static interface metadata only. It never searches
research content, reads external Skill files, or supplies Agent permission.

`SettingsToolbarAttachment` projects the six selected destinations to a native
preference `NSToolbar`. Its coordinator owns only exact-window attachment and
frame adjustment from the current top-left corner, constrained to the visible
screen and immediate under Reduce Motion. SwiftUI retains destination and
child-category state; feature owners retain configuration persistence. Native
search filters static page/control metadata and restores the browsing context.
`ScholiumHotkeyCommand` owns fixed and customizable menu bindings.
`ScholiumHotkeyPreferences` validates recording, writes and persisted overrides
against that catalog and native reservations. `ScholiumMenuShortcutModifier`
projects current preferences into menus; only customizable commands appear in
Settings. Fixed bindings have no second conflict-list definition.
`DocumentWebViewContainer` gives the focused document's registered shortcuts
to the native menu before WebKit, excluding hidden documents, other windows
and composition; disabled commands cannot fall through. Formatting and Find
use the existing editor bridge, while CodeMirror owns local text/navigation,
history and Save. Task-owned menu content receives the window command revision explicitly.
File, Edit, Format, Insert, View, Research and Window retain separate command
views. Research's Settlement route reuses the window toolbar's exact-target
availability and popover; it adds no mutation owner.

`SettingsInteractionView` composes Keyboard Shortcuts and Selection Actions
with a native segmented child selector. `SettingsIntegrationsView` composes
Agents & Chat and Zotero in the same way; it does not copy either feature's
state. Their scope notice is explanatory only and does not grant a broader
write authority.

The Metadata pane edits field definitions and About visibility/order as separate
parts of one revision-checked settings draft. It neither writes Note Metadata
nor source. The selected Triptych's Chat controller supplies connection settings
through the [Agent client](02-agent-collaboration.md#native-chat-client), not a
second runtime owned by the preferences window.

`SelectionActionPreferences` owns the ordered, enabled action definitions in
machine-local UserDefaults. The Settings pane retains editable drafts, validates
count, native label width and prompt size, and commits through that single owner.
The native selection menu reads those definitions; it owns no settings copy or
installed-Skill inventory.
