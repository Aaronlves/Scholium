# Scholium Editor Architecture

**Status:** Subordinate implementation contract

**Applies to:** CodeMirror 6, WKWebView, the app-private editor bridge, and editor-session integration

The Product Guide owns Scholium's product meaning and feature boundaries. The
Design Handbook owns interface structure, interaction, accessibility, and
exact user-facing language. This document records only the implementation
boundary that realizes those authorities; it cannot override either one.

> Scholium is a research-grade writing environment where philosophers can
> think naturally while the system preserves the exact intellectual artifact
> underneath.

## Governing invariants

1. One exact Markdown source is the only writable document authority.
2. Live Preview and Source share one persistent CodeMirror `EditorState`.
   Read renders the last fingerprint-bound committed revision.
3. CodeMirror owns the active editing state, selection, composition, and undo
   history. Swift owns a checked mirror reconstructed from accepted UTF-16
   deltas and reconciled against complete editor text before persistence.
4. `DocumentController` owns autosave, flush, conflict, external-change, and
   recovery coordination. `DocumentUseCases` owns fingerprint-gated commits.
   Formatting never enters Application or Core.
5. Contracts owns durable Markdown meanings and publishes the immutable
   `MarkdownEditingDialect`. TypeScript may parse an uncommitted buffer for
   immediate projection and exact transformations, but it cannot invent
   durable relationship, callout, diagnostic, or persistence semantics.
6. No command may normalize or reconstruct the document. Outside proven edit
   ranges, BOM, newline style, final newline, YAML, comments, unknown syntax,
   malformed source, and all other bytes remain unchanged.

## Boundary

```text
ScholiumContracts
        ↑
ScholiumApplication
        ↑
ScholiumApp
  DocumentController
    DocumentSessionStore
      MarkdownEditorSession
        WKWebView / CodeMirror
```

The bridge is a typed, bounded, identity- and generation-checked local
protocol. Mutating requests are serialized. Results are direct responses;
events describe editor-originated changes. It is not a generic event bus.
Source text crosses `WKWebView.callAsyncJavaScript` as structured arguments in
the page content world and is never interpolated into executable JavaScript.

Each request carries protocol version, request ID, session ID, document ID,
starting fingerprint, and expected generation. Deltas carry base and resulting
generations. Unknown operations, stale identities, generation gaps or repeats,
invalid or overlapping UTF-16 ranges, oversized messages, and oversized
results are rejected without mutation.

## Lifecycle and recovery

- Before autosave, manual Save, Read, Search, Dialogue, or Critique flushes,
  Swift requests the complete CodeMirror text and compares it with the checked
  mirror. Persistence proceeds only from a reconciled result.
- A clean external revision may replace the buffer with a generation-checked,
  non-history transaction. A dirty buffer remains exact and enters Conflict.
- Mode changes and structural commands wait for marked-text composition to
  finish and are discarded if document identity or generation changes first.
- When the WebKit content process terminates, the session reloads its controlled
  document and restores a matching bounded CodeMirror state snapshot. If the
  snapshot is unavailable, it reconstructs from the checked mirror and last
  selection. It never rereads disk over a dirty buffer. Loss of undo history is
  reported separately from source loss.

## Command contract

Every Markdown command is a closed app-private operation that creates one
CodeMirror transaction and one undo event. Multiple selections succeed
atomically or not at all. Transformations refuse frontmatter, code, raw HTML,
comments, protected literals, and malformed ranges whose boundaries cannot be
proved. Add Comment is not a Markdown command: it captures an exact selection
snapshot and opens the existing app-owned Comments workflow.

Command-F opens Scholium's shared **This Note** Search surface. The embedded
CodeMirror Find panel is not part of Scholium's editor architecture.

## Verification evidence

Pure TypeScript tests currently cover protocol validation, exact
transformations, single-transaction undo/redo, Lezer-backed representative
projection, Contracts parity fixtures, guarded lists and tables, and inert
clipboard conversion. Swift Testing covers the immutable Contracts dialect,
protocol encoding, architecture boundaries, controller convergence, and one
real WKWebView journey through initialization, exact CRLF reconciliation,
formatting, recovery reload, generation restoration, and Paste as Markdown.
The isolated QA app passes the canonical Live Preview editing and
commit-before-navigation journey, plus a focused journey proving that the
native Format, Insert, and editor context menus expose commands for the
focused session. Selection geometry, live composition, assistive
technologies, appearance settings, and sustained large-document editing still
require focused or manual QA before Editor 1.0 acceptance.

Performance claims follow `PERFORMANCE_BENCHMARK.md`. Measurements are evidence,
not release gates, until the release owner explicitly approves numeric gates.

## Non-goals

Editor 1.0 does not introduce Milkdown, ProseMirror, a hidden rich-text model,
HTML-to-Markdown persistence, Markdown normalization or repair, a permanent
formatting toolbar, arbitrary media management, citation management, embedded
AI chat or suggestions, real-time collaboration, a new SwiftPM target, or a
generic editor plugin framework.
