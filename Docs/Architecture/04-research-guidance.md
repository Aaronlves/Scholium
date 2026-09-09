# Architecture: Research Guidance

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Agent
Integration, Zotero configuration, and Settings ownership.

Research Guidance is an App Settings group, not an Agent runtime. Its current
destinations are **Agent Integration** and **External Tools**.

## Agent Integration

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
Researcher-owned method Skills remain in the external host and have no Scholium
registration, parser, store, editor, or recovery state.

## External Tools

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

Application and This Triptych settings retain their existing owners.
`WorkspaceSettingsModel` presents immutable snapshots and delegates writes to
Application capabilities. Portable Triptych settings contain Metadata
definitions, About order, Attention timing, and other declared portable state.
Unsupported pre-production state remains subject to the specification's
non-migration and byte-preservation boundaries; architecture adds no compatibility
policy.

Settings search indexes static interface metadata only. It never searches
research content, reads external Skill files, or supplies Agent permission.

`SettingsToolbarAttachment` projects the selected destination to a native
preference `NSToolbar`. Its coordinator owns only exact-window attachment and
frame adjustment from the current top-left corner, constrained to the visible
screen and immediate under Reduce Motion. SwiftUI retains destination state;
Application retains configuration persistence. Native search filters static
page/control metadata. Hotkey recording delegates to
`ScholiumHotkeyPreferences`, shared with command construction.

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
