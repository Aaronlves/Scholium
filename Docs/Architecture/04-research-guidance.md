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
does not expand Scholium's ten-tool MCP surface.

## Settings authority

Application and This Triptych settings retain their existing owners.
`WorkspaceSettingsModel` presents immutable snapshots and delegates writes to
Application capabilities. Portable Triptych settings contain Metadata
definitions, About order, Attention timing, and other declared portable state.
The retired Agent-created-analysis preference is decoded and re-encoded only as
opaque v8 compatibility data; it has no public, validation, or UI semantics.

Settings search indexes static interface metadata only. It never searches
research content, reads external Skill files, or supplies Agent permission.
