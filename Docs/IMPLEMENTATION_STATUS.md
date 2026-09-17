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
Settlement, guarded Note/file operations, note reorganization and Recovery.
Exact Markdown remains authoritative; YAML properties are authored in source,
not a separate managed metadata editor. File links and paragraph anchors refer
to current source, not snapshot citations or inferred philosophical evidence.

External Agents connect through the bundled App-mediated MCP helper. Note
operations, attachment reads, display, move previews and Agent Change review/Undo
retain the Application's source, revision and recovery owners. The helper requires
the running App; it is not a standalone/headless workspace product.

Optional in-app Chat reaches retained conversations, materials, runtime settings,
Skills/tools, questions and approvals, branching, concurrent turns and bounded
delegated-Agent observation. The bundled read-only Zotero integration and original
material navigation are reachable. Runtime reports, material access and mutation
receipts remain distinct from independently verified evidence or researcher
acceptance. There is no Research Action, Reading Lead, passage Discussion or Review
Comment lifecycle, external-host conversation handoff, or MCP research-result API.

The public release profile is Core App Beta. External Agent Collaboration and
optional in-app Chat remain Preview; reachability is not implicit acceptance.
The distribution is an App with bundled helpers. The latest artifact's exact proof
and incomplete clean-account smoke are recorded below; source reachability does
not establish packaged external-host, provider, physical-input or release acceptance.

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
