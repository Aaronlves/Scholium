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

The external MCP server exposes no Resources, Prompts, Tasks, model operation,
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

The mutation adapter consumes the machine-local `AgentChangeStore` and its
prepared/confirmed/uncertain evidence; persistence and eligible recovery are owned by
[Source Storage and Read
Models](05-source-storage-and-read-models.md#vault-write-and-prewrite-recovery-boundary).

## App presentation and setup

[Source Layout and Presentation](03-source-layout-and-presentation.md#presentation)
owns Agent Changes composition;
[Research Guidance](04-research-guidance.md#agent-integration) owns external-host
setup. Both consume this chapter's bridge and mutation-evidence owners.

## Native Chat client

`CodexAppServer` in Application owns one official stdio process, bounded JSONL
framing, correlation, timeouts, server-request replies and process teardown. It
implements no model/tool loop. Runtime authentication remains in the selected
Codex configuration directory. No credentials or raw stderr are copied to logs.

`WorkspaceStore.chatRegistry` owns one `AgentChatController` per Triptych across
windows. The controller owns selection, public messages, drafts, permission,
input delivery, approvals and one active turn. `AgentChatStorage` atomically
persists versioned machine-local history under `Chat/<triptych-id>`; a corrupt
archive blocks overwriting it. The default Codex home is `Chat/Codex`.

The runtime config registers the existing CLI MCP server with an execution token.
The CLI forwards that token in bridge schema 2. The App routes token-bearing
requests through the registry, binds the Triptych, applies conversation policy,
then calls the same `MCPAppBridgeRequestRouter`. External clients retain their
ordinary route and seven unchanged public tools. Ask-mode Note writes wait for
one native client approval; runtime approval requests are answered separately
only when they concern a different runtime operation.

`WindowChatActions` captures checked editor selection and resolves stable Note
references through the current catalog. `AgentChatView` consumes the shared controller;
it owns list/detail navigation, file popover and configuration input. Navigating back
does not stop the shared turn. Other conversations cannot become the execution target
while it is busy. Direct receipt sheets load only their requested change; a conversation
scope filters by its complete retained receipt IDs without collapsing successive changes
to a Note. Storage retains complete evidence. The controller owns archive/restore and
excludes archived conversations from sending. Machine path discovery and one-click
connection have one controller entry point; Settings receives the selected Triptych
controller from its composition root through environment injection, without giving
Settings a workspace runtime. The connection form and native file picker live only in
the Settings surface. The left selector is Library/Chat; Inspector exposes About/Links. Window close flushes drafts; runtime shutdown persists input and closes
its connection without global logout.

Conversation-token bridge requests allow 590 seconds for researcher input and
execution, with a 600-second client deadline. Cancellation removes ungranted
approvals before returning. Ordinary external requests keep the existing
25/30-second budgets; the local bridge remains serialized.

`AgentChatMarkdown` uses Foundation Markdown presentation intents with native
SwiftUI text, lists, code and comparison rows. `AgentChatTimelineItem` groups
contiguous operation messages for disclosure without shortening public replies.
`AgentChatActivityProjection` translates public runtime items and App bridge
receipts into typed activity. The controller publishes bridge activity before
waiting or executing, updates the same message at completion, and suppresses
the duplicate runtime envelope for its registered Scholium tools. Reopened
unfinished activity is interrupted or uncertain until authoritative runtime
history supplies a terminal result. `AgentChatFileSummary` projects observed
file effects and receipt identities; it owns neither filesystem state nor Undo.
