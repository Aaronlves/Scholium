---
name: scholium-agent-collaboration
description: "Implement, diagnose, or test Scholium external-Agent collaboration through the local MCP/App bridge, guarded Note operations, and Agent Changes. Exclude philosophical method content, interface-only changes, source parsing, retrieval ranking, and release acceptance."
---

# Scholium Agent Collaboration

Own the functional boundary between an external Agent and the running App,
including mutation evidence and exact mutation evidence. Conversation and
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

## Method

1. Trace one current request from MCP entry through bridge routing, selected
   open Triptych, Application operation, persistence, and returned result.
2. Distinguish Note identity and source revision, transport authentication,
   Agent Change evidence, and mutation recovery. Locate each writer and
   projection before changing it.
3. Inspect stale identities, unavailable App/workspace state, concurrent editor
   changes, failures, uncertain writes, and retry behavior relevant to that
   operation. Do not infer safe replay from transport success or failure.
4. Change the owning boundary and its affected schemas, callers, and focused
   tests together. Preserve one Application operation across delivery adapters.
5. Verify the actual operation and its affected failure/recovery paths using
   disposable fixtures under the repository's verification rules.

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
