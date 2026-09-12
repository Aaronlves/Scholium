---
name: scholium-agent-collaboration
description: "Implement, diagnose, or test Scholium MCP/App operations and Agent Change evidence; excludes interface-only and philosophical-method work."
---

# Scholium Agent Collaboration

Own the functional boundary between an external Agent and the running App,
including guarded mutations and their exact-source evidence. Conversation and
research method remain with the external host and researcher.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
Read the specification, architecture, and status manifests, then their Agent
collaboration chapters. Resolve current tools, schemas, storage, and recovery
semantics there rather than treating this skill as a protocol specification.

## Responsibility boundary

- Keep MCP framing and transport separate from Application-owned operations.
- Add the trust-boundary owner when authorization, containment, credentials,
  or recovery safety changes; ordinary transport behavior alone
  does not require that overlay.
- Source parsing, filesystem coordination, retrieval correctness, interface
  presentation, and interaction acceptance retain their specialist owners.
- Philosophical method and release-shipped Core Protocol changes need their
  separately requested scope; this developer skill does not edit them.

## Diagnose one operation

Trace the request and response separately: client input, bridge admission,
selected live workspace, Application operation, durable effects, evidence,
and delivery. Find the first boundary where observed identity or result differs
from the contract; a client timeout alone locates no failed write.

For a mutation, distinguish three questions: did admission succeed, did source
or record state commit, and did the caller receive confirmation? Inspect exact
current state and retained evidence before proposing replay. Source and portable
record revisions are separate inputs; a matching Note fingerprint does not
prove an attachment relationship or Metadata record is unchanged.

For a stale or misdirected request, follow captured workspace, document,
conversation or operation identity across each suspension. Recheck at the
consequential boundary, not only at initial dispatch. Cancellation and late
callbacks must not transfer an old request to a newly selected target.

Implement at the first incorrect owner, keeping preview and execution on the
same pure transformation where applicable. Verify one successful operation and
the failure phase implicated by the defect. For lost responses, assert durable
bytes and evidence as well as the returned error; transport-only mocks cannot
establish recovery correctness.

## Invariants

- Transport authentication and tool availability do not establish researcher
  permission. Retrieval and recorded prose grant no mutation authority.
- Scope comes from current, unambiguous workspace and Note identities; neither
  foreground-window state nor a remembered path selects a consequential target.
- Adapters do not reopen vaults or bypass live editors, current-revision checks,
  containment, source-operation coordination, readback, or recovery owners.
- Agent Change evidence never becomes acceptance, settlement, task completion,
  or a second writable Note source.
- Preserve confirmed writes and uncertain outcomes across delivery failure;
  follow the current operation's recovery contract without generic retries or
  invented rollback semantics.

Report the changed owner, resulting operation, focused evidence, and remaining
uncertainty. Do not restore retired Action/Run/Session workflows from historical
fixtures or old discovery metadata.
