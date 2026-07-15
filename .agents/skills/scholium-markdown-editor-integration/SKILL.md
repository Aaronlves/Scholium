---
name: scholium-markdown-editor-integration
description: Develop, review, test, or diagnose Scholium's active CodeMirror 6 and WKWebView Markdown boundary. Use for MarkdownEditorWebView, SafeMarkdownReadWebView, MarkdownEditorSession, EditorSource, bridge envelopes, versioned UTF-16 deltas, full-buffer reconciliation, Read/Live Preview/Source transitions, syntax projection, autosave, selection, undo, focus, IME composition, accessibility, CSP or navigation policy, editor bundle generation, or the native fallback views.
---

# Scholium Markdown Editor Integration

Preserve one exact Markdown buffer across editing, persistence, and presentation. Treat every rendered or decorated form as a projection that must never become writable source.

## Locate the checkout

Bind one repository root containing `AGENTS.md`, `Package.swift`, `ScholiumCore/`, and `Scholium/`. Do not derive the checkout from an installed plugin cache. If no unique root is in scope, stop and request it. Resolve paths below from the repository root.

Pair this skill with `scholium-development` for final verification, `scholium-markdown-yaml-fidelity` for exact document boundaries, `scholium-vault-file-coordination` for external-edit races, `scholium-trust-boundary-audit` for WebKit and save authorization, `scholium-apple-design` for interaction and accessibility, and `scholium-ui-automation` for real app workflows.

## Confirm the active architecture

Inspect construction call sites before changing a framework. The active path is:

- `Scholium/Views/Note/NoteContentView.swift` owns modes, autosave, conflicts, and the source binding;
- `MarkdownEditorWebView.swift`, `MarkdownEditorSession`, and `WebEditor/editor.ts` provide one persistent CodeMirror 6 surface for Source and Live Preview;
- `SafeMarkdownReadWebView.swift` presents sanitized HTML produced from the fingerprint-bound semantic document in Read mode;
- `NativeMarkdownReadView` is a fallback, including isolated UI-test fallback use; `NativeMarkdownEditorView` is not the active editor.

Treat the native path as fallback-only unless reachable call sites and the task explicitly reactivate it. Do not redesign production behavior around native files merely because they remain in the tree.

## Preserve and reconcile one buffer

- Load CodeMirror from the exact `NoteDocument.rawContent`; preserve BOM, newline convention, malformed frontmatter, unknown syntax, and final newline.
- Keep CodeMirror's document as the editing-session authority and the Swift string as a checked mirror. Never reconstruct Markdown from HTML, decorations, parsed YAML, attributed text, or semantic nodes.
- Send edits as contiguous, versioned CodeMirror offsets. CodeMirror and JavaScript offsets are UTF-16; apply them with `NSString`-compatible bounds, never `String.count`.
- Validate every edit envelope against bridge version, editor session, document ID, starting fingerprint, payload bounds, and exactly the next document version. Reject gaps, repeats, stale sessions, invalid ranges, and oversized insertions.
- Before every manual save or debounced autosave, request `MarkdownEditorSession.currentText()`. Compare the complete CodeMirror buffer with the delta-derived Swift mirror, reconcile the binding to the returned buffer, and save only that exact reconciled string. A failed request or unexplained mismatch must keep the editor dirty and visible; it must not fall back to a possibly stale mirror.
- Keep full-buffer reconciliation inside the same expected-revision, snapshot, validation, and atomic-write pipeline. It is a consistency check, not permission to overwrite an external change.
- Clear dirty state only after committed bytes, revision, search, graph, and rendering state have advanced successfully. Bind delayed save, focus, parse, and navigation work to the active vault, path, fingerprint, session, and document version.

## Keep projection reversible

- Reconfigure Source and Live Preview on the persistent CodeMirror state; do not replace the source buffer during a mode change.
- Build Live Preview decorations only for the visible viewport and semantic context needed around it. Reveal exact markers when the selection enters a construct.
- Exclude frontmatter, comments, escaped constructs, inline code, fenced code, HTML literals, and other literal ranges from semantic decoration as required by `MarkdownSemanticDocument`.
- Preserve selection, scroll position, history, completion state, and first responder across projection updates. Do not add decoration work to undo history.
- Enter Read only after reconciling and committing pending edits. Render sanitized HTML from the same committed fingerprint and keep source-line navigation and internal-link activation bound to that document.

Read [references/webkit-bridge-checklist.md](references/webkit-bridge-checklist.md) before changing the active editor or reader bridge. Read [references/native-editor-checklist.md](references/native-editor-checklist.md) only when maintaining or deliberately reactivating the native fallback.

## Constrain WebKit

- Use a nonpersistent data store, an explicit content-security policy, bounded typed messages, and a fixed set of handlers.
- Keep remote connections and subresources disabled. Allow only the controlled initial document load; route approved external links through explicit native policy and reject unexpected navigation.
- Encode Swift-to-JavaScript values as JSON rather than interpolating source text. Surface evaluation, load, and bridge failures without losing the editing buffer.
- Remove handlers and cancel startup, focus, and synchronization work during teardown.

## Preserve composition and accessibility

- Do not replace the CodeMirror document or force selection while an IME composition is active. Test CJK input, composed accents, emoji, RTL text, dictation, and rapid undo/redo.
- Preserve standard find/replace, spelling, text services, copy/paste, multi-line selection, keyboard navigation, and focus behavior.
- Give the editor an accurate mode-specific accessible label. Give replacement widgets meaningful labels without hiding the editable source from assistive technology; projected punctuation must reappear when editing its construct.
- Verify VoiceOver reading order, keyboard-only use, increased contrast, reduced transparency, enlarged text, and focus recovery after sheets and conflicts.

## Rebuild generated editor assets deliberately

Treat `WebEditor/editor.ts`, `package.json`, and `package-lock.json` as source and `Scholium/Resources/Editor/editor.bundle.js` as generated output. After TypeScript or dependency changes, run:

```bash
./Tools/Scripts/build-editor.sh
./Tools/Scripts/verify-editor-bundle.sh
```

Run `./Tools/Scripts/verify-editor-bundle.sh` during ordinary verification even when the editor source did not change. Keep locked dependencies and third-party notices current; never hand-edit the generated bundle.

## Verify

Test exact source and visible behavior for emoji and combining marks, BOM/CRLF, malformed and missing frontmatter, empty and large notes, rapid A -> B -> A switching, Source <-> Live Preview <-> Read transitions, out-of-order deltas, full-buffer mismatch, failed autosave, external conflicts, teardown/recreation, IME composition, undo, focus, selection at projected boundaries, malicious messages, and blocked navigation.

Run focused editor and semantic tests, `./Tools/Scripts/verify-editor-bundle.sh`, then `./Tools/Scripts/verify.sh`. Use `scholium-ui-automation` for responder-chain, composition, accessibility, and packaged QA-app interaction with disposable fixtures and isolated app state. Never validate against a private research vault or capture private note content.
