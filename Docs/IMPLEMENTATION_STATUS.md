# Scholium Implementation Status

- **Target authority:** [SCHOLIUM_SPEC.md](SCHOLIUM_SPEC.md)
- **Structural reference:** [IMPLEMENTATION_ARCHITECTURE.md](IMPLEMENTATION_ARCHITECTURE.md)
- **Evidence dates:** per entry; no whole-app or human-acceptance pass implied.

This is the sole entry point and closed manifest for implementation status.
It records the current reachability profile, remaining work and consequential
proof boundaries, not a second feature specification or source-code inventory.
Live construction, tests and scripts establish precise current behavior.

## Current reachability profile

The native App reaches a registered three-vault Triptych, Library and document
tabs, Review/Edit/Source, source-derived Search and Links, Writing References,
Changes, guarded Note/file operations, note reorganization and Recovery.
External Markdown opens independently and imports to a selected Triptych role.
Exact Markdown remains authoritative; YAML is authored source. The Zotero
citation adapter reaches body fields, bold/italic fallback and static exports.
Live picker/insertion and bibliography rendering have bounded native proof;
post-repair Refresh/style and offline recovery acceptance remain pending.

External Agents connect through the bundled App-mediated MCP helper. Note
operations, attachment reads, display, move previews and Agent Change inspection/Undo
retain the Application's source, revision and recovery owners. The helper requires
the running App; it is not a standalone/headless workspace product.

Optional in-app Chat reaches conversations, materials, runtime settings,
Skills/tools, questions/approvals, branching, concurrent turns and delegated-Agent
observation. Managed `scholium-zotero` reads via localhost API/Connector and
updates version-checked items with Zotero authorization. Original reads use
App-mediated read-only file/folder grants; indexed text has revision-bound
UTF-8 continuation. Agent imports remain
unavailable without prewrite target binding; native service owns status. Reports,
access and receipts remain distinct from evidence. No research-result lifecycle
or API is exposed. Storage reaches inspected cleanup of unused Chat copies;
citation Recovery exposes retained copies for inspection without applying them.

Core App Beta is public; external Agent Collaboration and optional Chat remain
Preview. The App and helpers update together. Sparkle supports application
updates through GitHub Releases and the deployed HTTPS feed. Artifact proof stays
tag-specific; source reachability establishes no packaged external-host,
managed-Zotero, physical-input or release acceptance.

## Status chapters

| Question | Chapter |
| --- | --- |
| What implementation, environment or acceptance work remains? | [Open Work](Status/03-open-work.md) |
| What dated proof, measurement and release provenance can be carried forward? | [Verification Evidence](Status/04-verification.md) |

Open Work contains only unresolved implementation and acceptance. Verification
retains representative evidence and useful measurement comparisons, not completed
task narratives. Keep exact source, toolchain, artifact, fixture, procedure and
result provenance when supporting gate/release acceptance. Test counts from
separate runs are not additive; Git owns superseded details.
