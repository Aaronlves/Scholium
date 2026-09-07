# Architecture: Agent Collaboration

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Local MCP,
mutation evidence, and Settings ownership.

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

`ScholiumMCPToolName` defines exactly seven tools with closed schemas:

- workspace status;
- Note Search and exact Note reads;
- authored link occurrence listing; and
- exact Note create, update, and system-Trash mutations.

The server exposes no Resources, Prompts, Tasks, model operation, chat,
Handoff, Research Action, acceptance, Review, Settle, or research-result
endpoint. Tool availability is not write permission.

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

Operation History remains a separate native collection and read-only comparison over machine-local Note
mutation evidence. This surface does not own conversation, permission, review,
acceptance, or Settlement.

`AgentIntegrationSettingsView` reports App, bridge, and CLI availability,
copies the Codex or Claude user-scope registration command using the verified
absolute CLI path, and reveals the release-bundled Core Protocol. It never
changes host configuration or installs researcher-owned Skills.
