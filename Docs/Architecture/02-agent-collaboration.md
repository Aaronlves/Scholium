# Architecture: Agent Collaboration

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Local MCP,
Research Records, mutation evidence, and Settings ownership.

## Delivery path

`scholium mcp serve` is a stdio adapter. `ScholiumMCPServer` owns JSON-RPC
framing, initialization, fixed tool discovery, closed input/output schemas,
annotations, and MCP error envelopes. `MCPCommandHandler` owns stdin/stdout
only.

The CLI calls `ScholiumAppBridge`, which discovers one current-user App
endpoint and authenticates the live process. It does not construct a workspace
runtime, start the App, or access Triptych files. `ScholiumAppBridgeRequestRouter`
validates the bridge request and delegates one tool call to
`MCPAppBridgeRequestRouter`.

The App router operates only on currently open `WindowSession` capabilities.
Workspace selection is automatic only for exactly one open Triptych. Multiple
open Triptychs require the caller's exact stable Triptych identity.

## Fixed tool surface

`ScholiumMCPToolName` defines exactly ten tools with closed schemas:

- workspace status;
- provider-separated Note/Record Search;
- exact Note and paged Record reads;
- authored link occurrence listing;
- exact Note create, update, and system-Trash mutations; and
- attributed Record creation/append plus append-only step correction.

The server exposes no Resources, Prompts, Tasks, model operation, chat,
Handoff, Research Action, acceptance, Review, Settle, or research-result
endpoint. Tool availability is not write permission.

## Research Record authority

`ResearchRecordStore` is the sole writable owner of strict schema-1 files under
`.scholium/inquiry-records/v1/`. One Record is one continuing inquiry question;
its ordered steps retain external-Agent attribution, substantive time,
revision relations, exact Note references, and append-only clerical
corrections. Store reads isolate a damaged file while preserving other valid
Records. Writes use descriptor-relative containment, a cooperating-process
lock, expected Record-file fingerprints, atomic replacement, and decoded
readback.

`WorkspaceHandle` validates every referenced stable Note identity and exact
Note fingerprint against a refreshed authoritative workspace before a Record
write. A stale or ambiguous reference fails without creating or changing a
Record. Record writes do not produce `AgentChange` entries because they are
already attributed research history rather than Note-source mutations.

The bundled `scholium-core-protocol` tells an external Agent to decide whether
each substantive step continues an existing independently developing question
or begins a new one. This method policy is outside MCP: MCP validates only
identity, shape, currentness, and storage. A Record never establishes truth,
researcher acceptance, Review, Settle, permission, or completion.

## Search and read projections

`ResearchRecordSearchIndex` is a disposable provider-local projection over the
strict store. It indexes current questions and current projected step bodies,
uses its own manifest/generation, ordering, totals, offsets, and continuation,
and never writes Record authority. `DiscoveryOperations.unifiedSearch` invokes
Note and Record providers independently for **All**, or one provider for the
dedicated path. Scope filtering uses exact stable Note references; rankings are
never interleaved.

`scholium_read_record` returns a bounded chronological step slice plus original
body, current projection, correction history, attribution, Note references,
and complete Record-file fingerprint. It does not substitute current Note prose
for a historical reference.

## Note mutation authority and evidence

Every Note mutation first flushes matching live editors and enters the existing
workspace source-operation gate. Create proves an exact vacant `.md` path and
commits the common managed scaffold plus stable Note identity. Update preserves
either the complete YAML envelope or replaces the explicitly authorized full
source, depending on its mode. Update and Trash compare the caller's exact
fingerprint with current source before commit.

Application repositories retain containment, atomic replacement, native Trash,
readback, identity recovery, and complete derived refresh ownership. The bridge
never bypasses those owners.

`AgentChangeStore` is machine-local and records one prepared/confirmed or
uncertain change per Note mutation. Confirmed update evidence retains exact
preimage and final fingerprints. Direct Undo is available only while current
source still equals the recorded final revision. Create and Trash have no
fabricated source restore.

## App presentation and setup

Research Records use one read-only, Triptych-bound window. Its collection uses
the Record provider; its detail shows the question, chronological attributed
steps, bounded Markdown projection, and optional Note-evidence rail. A
Triptych-keyed coordinator routes Search selections to the existing window but
retains no Record data. The window polls the strict store while visible so an
external Agent append refreshes without activation or focus movement.

Agent Changes remain a separate read-only presentation over machine-local Note
mutation evidence. Neither surface owns conversation, permission, review,
acceptance, or Settlement.

`AgentIntegrationSettingsView` reports App, bridge, and CLI availability,
copies the Codex or Claude user-scope registration command using the verified
absolute CLI path, and reveals the release-bundled Core Protocol. It never
changes host configuration or installs researcher-owned Skills.
