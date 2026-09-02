# Architecture: Agent Collaboration

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Local MCP,
App bridge, mutation evidence, and Settings ownership.

## Delivery path

`scholium mcp serve` is a stdio adapter. `ScholiumMCPServer` owns JSON-RPC
framing, initialization, fixed tool discovery, closed schema validation, and
MCP error envelopes. `MCPCommandHandler` owns stdin/stdout only.

The CLI calls `ScholiumAppBridge`, which discovers one current-user App
endpoint and authenticates the live process. It does not construct a workspace
runtime, start the App, or access Triptych files. `ScholiumAppBridgeRequestRouter`
validates the bridge request and delegates one tool call to
`MCPAppBridgeRequestRouter`.

The App router operates only on currently open `WindowSession` capabilities.
Workspace selection is automatic only for exactly one open Triptych. Multiple
open Triptychs require the caller's exact stable Triptych identity.

## Fixed tool surface

`ScholiumMCPToolCatalog` defines the only seven tools and their closed schemas:

- workspace status;
- Note search, exact read, and authored link listing; and
- exact create, update, and system-Trash mutations.

Search reuses the Application-owned Note Search path. Read and link results use
current immutable workspace snapshots and exact source locators. The adapter
exposes no Resources, Prompts, Tasks, model operation, chat, Handoff, Research
Action, Research Record, or lifecycle endpoint.

## Mutation authority and evidence

Every mutation first flushes matching live editors and enters the existing
workspace source-operation gate. Create proves an exact vacant `.md` path and
commits the common managed scaffold plus stable Note identity. Update preserves
either the complete YAML envelope or replaces the explicitly authorized full
source, depending on its mode. Update and Trash compare the caller's exact
fingerprint with current source before commit.

Application repositories retain containment, atomic replacement, native Trash,
readback, identity recovery, and complete derived refresh ownership. The bridge
never bypasses those owners.

`AgentChangeStore` is machine-local and records one prepared/confirmed or
uncertain change per mutation. Confirmed update evidence retains exact preimage
and final fingerprints. Direct Undo is an Application operation available only
while current source still equals the recorded final revision. Create and Trash
have no fabricated source restore.

## App presentation and setup

Agent Changes are a read-only App presentation over machine-local evidence.
They do not own conversation, permission, review, acceptance, or Settlement.

`AgentIntegrationSettingsView` reports App, bridge, and CLI availability,
copies the Codex or Claude user-scope registration command using the verified
absolute CLI path, and reveals the release-bundled Core Protocol. It never
changes host configuration or installs researcher-owned Skills.

The only bundled collaboration Skill is
`scholium-core-protocol`. `BundledResearchSkillResources` exposes that
protected folder for Finder presentation; Scholium does not register or execute
method Skills.
