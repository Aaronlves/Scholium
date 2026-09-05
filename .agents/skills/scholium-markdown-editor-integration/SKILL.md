---
name: scholium-markdown-editor-integration
description: "Implement, diagnose, or test Scholium's active Markdown editor and reader boundary. Use for CodeMirror or WKWebView bridging, text reconciliation, presentation modes, selection, undo, focus, IME, accessibility, content security, or generated assets."
---

# Scholium Markdown Editor Integration

Preserve one exact Markdown buffer across editing, persistence, and
presentation. Rendered or decorated forms never become writable source.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).

## Method

1. Locate the reachable editor, persistent session, bridge, reader, and
   generated assets from live construction and tests.
2. Trace exact source from authoritative read through editing, reconciliation,
   transactional save, committed read-back, and reader presentation.
3. Load the [WebKit bridge checklist](references/webkit-bridge-checklist.md) for
   the active bridge.
4. Change the smallest owning boundary and regenerate assets through current
   repository scripts rather than editing generated output.
5. Verify source fidelity together with session behavior, input services,
   accessibility, failure, conflict, and recovery.

## Invariants

- One editing session owns text history; native code may hold only a checked
  mirror. Never reconstruct Markdown from HTML, decorations, parsed metadata,
  or semantic nodes.
- Bridge changes are versioned, bounded, ordered, and bound to document,
  session, and starting revision. Reject stale, repeated, skipped, or invalid
  messages.
- Reconcile the live full buffer before persistence and keep unexplained
  mismatch visible and dirty. Reconciliation never authorizes overwriting an
  external change.
- Presentation changes preserve source, selection, scroll, undo, focus,
  composition, marked text, and current identity. Decorations do not enter
  history.
- Reader output is derived from the committed revision and cannot grant
  mutation authority.
- Keep the Web boundary local, typed, size-bounded, navigation-controlled, and
  free of ambient network or filesystem access.
- Do not replace text or force selection during composition. Preserve standard
  keyboard, accessibility, clipboard, spelling, find, and text-service paths.

## Evidence

Use disposable documents spanning the affected source and Unicode boundaries,
then exercise ordering, switching, mismatch, save failure, conflict, process
recovery, composition, undo, focus, and accessibility as applicable. Run the
current editor asset checks and focused suites; use isolated UI automation for
runtime-only claims. Apply the verification cadence in `AGENTS.md`; do not
infer a complete repository or UI gate from editor scope. Report any input path
not exercised.
