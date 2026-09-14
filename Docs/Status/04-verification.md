# Implementation Status: Verification Evidence

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Dated proof and its limits.

## Current verification snapshot

**2026-09-14 — Paragraph reuse and academic Note reorganization:** 57 scoped Core,
33 App and five Contracts tests pass with Xcode 27. Coverage includes footnote
resource relocation across folders (CRLF, Tab, Unicode and multiline labels),
reference-scope isolation and literal escaping, independent YAML comments and
scalar values, clean background-session convergence and dirty conflicts. A real
WKWebView test confirms the exact disk commit and receipt survive detachment before
save acknowledgement. Existing identity, cancellation and destination-table checks
also pass. The complete background-tab insertion GUI journey remains unverified.
Evidence: `.build/knowledge-reuse-fixes-tests.log`,
`.build/knowledge-reuse-fixes-dialect.log` and `.build/knowledge-reuse-fixes-research.md`.
Earlier standard 500-Note disposable Triptych QA plus three synthetic Notes verified Related Material
paragraph insertion, destination Undo/Redo, initially unselected YAML choices,
three-file preview, Escape cancellation with unchanged bytes, and native Merge.
Exact readback confirms selected properties, retained target content, renamed
footnotes and incoming references following the same anchor; the original leaves
the vault through native Trash. Dark-window screenshots were inspected. Full human
input/accessibility and adaptation acceptance remain open. QA app, fixtures,
state were removed. macOS denied access to `QA Reuse Source.md` in Trash, so its
post-Trash bytes and cleanup were not verified and that item remains. Evidence:
`.build/knowledge-reuse-tests.log`, `.build/knowledge-reuse-qa.md` and
`.build/knowledge-reuse-qa-build.log`. Documentation and scoped Swift lint pass.
The full repository gate stops at the unchanged `input-suggestions.ts`
localization false positive; `.build/knowledge-reuse-fixes-gate.log` records
that failure, not an integration pass.

**2026-09-14 — Preview renderer reuse:** An opt-in native-owner diagnostic uses
eight disclosures per build (one cold, seven subsequent) on Xcode 27 Debug,
macOS 27 and synthetic mixed-script content. Subsequent synchronous preparation
falls from 35.7–47.8 ms to 0.66–1.41 ms; request-to-prepared-presentation median
falls from 84.3 ms to 29.5 ms. The renderer is reused only within its document
host; navigation identity/generation guard replacement, and host reset releases
it. Eight scoped native/Edit/Review checks pass for replacement, cancellation,
scroll, focus and source preservation. This isolates native preparation, excluding hover delay, bridge transport
and animation completion; cold initialization and perceived smoothness are not
accepted by this diagnostic. Logs: `.build/preview-latency-before.log`,
`.build/preview-latency-after.log`, `.build/preview-perf-tests.log` and
`.build/preview-perf-reader-tests.log`.

**2026-09-14 — Editor candidates and ordinary deletion:** Slash commands share
CodeMirror's editing/AX owner and retained native choice list; the separate menu
and key forwarding are removed. Typechecking and 41 focused candidate/protocol
Web tests pass. Thirty-five projection tests compare repeated mixed-script
and line-end deletion against a fresh index. On a 58,340 UTF-16 synthetic Note,
three runs of 24 ordinary line-end deletions reduce full index rebuilds from
24 to zero and per-run state-update medians from 4.26–5.29 ms to 0.53–0.68 ms.
Structural, multiline and unsafe deletions still rebuild. A real WebView
input/deletion check preserves exact Web text, native mirror and caret; its
throttled frame callbacks supply no paint-latency evidence. Native protocol
checks pass. The final slash journey passes filtering, continuous Backspace,
acceptance/Undo, retained focus and no menu tracking; isolated QA confirms direct
Backspace after `/` and continued input/deletion. Evidence: `.build/slash-list-web-tests.log`,
`.build/slash-candidates-journey.log`, `.build/deletion-tests.log`,
`.build/deletion-native-tests.log` and `.build/deletion-performance-notes.md`.
The owning WebView check also passes with native secondary selection, preserving
pointer/keyboard selection and editor focus; `.build/floating-emphasis-tests.log`.
Hover strength, VoiceOver, full IME and appearance/adaptation acceptance remain
open. This is scoped development evidence, not a full gate or human acceptance.

**2026-09-14 — Native document previews:** Twelve scoped native/Editor/Review
checks pass for bounded first measurement, repeated and replaced targets,
source/selection/Undo preservation, footnotes, annotations, Escape and composition.
Xcode 27 Debug QA with a disposable standard Triptych copy confirms native short
and long presentations, annotation toggle, retained editor focus, Escape and
readable accessibility content after WebKit's lazy AX initialization. Physical
cross-window scrolling, VoiceOver and the full appearance/input-service matrix
remain unverified; the automation scroll route targeted the originating window.
This is scoped development evidence, not release or human acceptance.

**2026-09-14 — Native research sheets:** Twenty-four scoped checks pass across
native two/three-column layout, both collection scopes, exact comparisons,
Viewed timing and a real SwiftUI sheet lifecycle. The lifecycle check displays
an actual parent window and verifies its frame through loading, detail and full
dismissal. Two adaptation checks also pass after aligning their host with the
sheet minimum height. Debug build, localization, scoped formatting and
documentation validation pass. Final disposable-fixture QA confirms automatic
Viewed after opening detail, absent technical/manual-viewing controls, stable
list/detail navigation, and destination search → keyboard selection → preview
→ cancellation with unchanged source. AppKit owns native column allocation;
header dragging and imperative sheet resizing are removed. Light/Dark and
narrow/high-contrast component renders were inspected. Full assistive-technology,
IME and release acceptance remain open. No full repository gate was run.
Evidence: `.build/native-research-sheet-tests.log`,
`.build/native-research-sheets-qa.md`, `.build/agent-changes-review/` and
`.build/note-picker-review/`. The isolated QA bundle and state were removed.

**2026-09-14 — Note actions and paragraph reorganization:** The integration
execution passes Core 367 plus 3 performance tests, Contracts 81, and Application
164 plus 1 architecture measurement. The App run executes 854 tests with one
failure: its old toolbar-order expectation omitted More. Updating that assertion
passes all 77 owning architecture tests; the full App product was not repeated
after this test-only correction. A matching-fingerprint malformed semantic cache
initially exposed an anchor-parser bounds exception; source-coordinate validation
and fresh parsing resolve it before the complete Core rerun. Nine focused App
checks also pass for exact paragraph selection, hidden identities and the real
WebView selection/Undo bridge. Typechecking, 262 editor tests, reproducible bundles,
localization, Swift formatting, documentation, public-symbol boundaries, Release
build (166.67 seconds) and the bundled-helper checks pass. Gate phases were
completed in stages; this is not a claim of a single uninterrupted green run.

Disposable-fixture AX QA confirms main More after Review/Edit, one separate More
with correct window commands, separate Find-field focus, native Copy Note Link
visibility and exact clipboard delivery. Cold-start paragraph-link creation saves
its anchor before copying and preserves neighboring source. Extract retains its
ID and redirects incoming links; Review Copy assigns a new ID and retains the
original. Partial selection is refused and cancellation works. Native first-item
hiding and invalid/nested anchor projections have regression tests. Screenshot
capture was unavailable; visual adaptations, native Trash-merge and human
acceptance remain open. QA bundle and temporary state were removed. Evidence:
`.build/note-actions-qa.md`, `.build/note-actions-integration.log`,
`.build/note-actions-integration-resumed.log`, `.build/note-actions-integration-final.log`,
`.build/note-actions-final-boundaries.log` and `.build/paragraph-anchor-semantic-safety-tests.log`.

**2026-09-14 — Triptych Chat workspace:** Eight integration checks pass for
control-store routing, isolated workspaces and Skills with shared login,
discovery, renewal, cancellation, failure/retry, containment and Settings
renders. Installed Codex confirms Skill discovery and the Chat working directory
without model inference. Selection and active-turn configuration, Light/Dark,
localization, documentation, Release build, helper smoke and public-symbol
checks pass. AGENTS.md model consumption, Finder interaction and human
accessibility acceptance remain open. The associated gate reported Core 353+3,
Contracts 73, Application 164+1 and 840 App tests with eight issues in two
tests. Four focused Find checks pass after a measurement-control correction;
the complete gate was not rerun and is not green. Logs: `.build/chat-workspace/`
and `.build/verification/`.

**2026-09-13 — Late concurrent source preservation:** Two independent
late-writer reproductions return Recovery Required and retain exact external
bytes. One hundred eleven selected tests pass across Core, Application and the
App MCP router, covering process interruption, failed retention, deferred
cleanup, revision-checked restoration and move/Agent Undo. Formatting and
documentation authority also pass. This is scoped source/fixture proof;
installed-release, live sync-provider and human Recovery acceptance remain open.
Logs: `.build/note-safety-fix/`.

**2026-09-13 — Reader arrival and formatting:** Review waits for its destination
before capturing the anchor and receipt. The original four assertions pass;
135 native WebKit tests, 255 editor tests, resource reproducibility and
repository-wide Swift formatting pass. This is not a complete repository-gate,
packaged or human-acceptance result. Logs: `.build/repair-webkit.log`,
`.build/repair-editor-verification.log` and `.build/repair-format-after.log`.

**2026-09-13 — App-only delivery:** The App-only cutover passed 110 owning
tests, Debug/Release helper smoke, public-symbol checks and a Release build.
Core, Contracts and Application integration checks passed in the reported
scopes. The original full gate remains a failed historical run; no new artifact
or clean-account acceptance was established. Logs: `.build/cli-removal-*.log`
and `.build/verification/`.

**2026-09-13 — Source-authority cutover:** Core, Contracts and Application
checks passed, with affected App behavior checks, resource, formatting,
documentation and localization checks. Native QA covered Links navigation,
YAML Search and source-linked attachments. No final one-shot repository rerun
was claimed; provider and complete accessibility/adaptation acceptance remain
open. Logs: `.build/source-cutover/verification.md`.

**2026-09-10 — Chat foundation:** The focused checks and Debug QA covered
scrolling, quotes, previews and shared message typography. Packaging,
large-history and accessibility/adaptation acceptance remain open. Logs:
`.build/agent-foundation-acceptance.md`.

**2026-09-08 — Signed-in research loop:** Disposable 500-Note QA with the
official Codex runtime completed a bounded multi-turn read, native approval,
one exact Note update, comparison, Undo, restart restoration and Stop. The
changed Note returned to its starting bytes. This closes CHAT-LIVE-01 and
CHAT-LIVE-02 only for that path. Provider breadth, concurrency and human
accessibility acceptance remain separate. Evidence:
`.build/agent-chat-evolution/real-loop-retest-*.json`.

**2026-09-07 — Editor syntax continuity:** 228 editor tests, TypeScript and
resource reproduction, Debug App/test compilation and 16 Swift/WebKit checks
passed. Fixture QA covered Callout placement, Chinese paste/Undo, disclosure,
Light/Dark, doubled text and mode switching; Undo restored identical bytes.
Minimum-width, system-adaptation, IME, conflict/recovery and human perceptual
acceptance remain open. Evidence: `.build/editor-presentation-*.log`.

## Evidence boundary

These entries retain one current representative result for each active proof
boundary, not a per-change transcript. Test counts from separate runs are not
additive. Focused tests, offscreen renders, Debug QA and deterministic fixtures
prove only their named scope; they do not establish packaged behavior, G7/G9,
VoiceOver, Full Keyboard Access, installed Simplified Chinese IME, physical
input, or full visual adaptation unless explicitly stated.

Current capabilities belong to [Reachable Capabilities](01-capabilities.md),
user-facing reachability to [Reachable Interface](02-interface.md), and open
implementation or acceptance work to [Open Work](03-open-work.md). Target rules
remain in the Specification set. Superseded task narratives belong to Git
history; `.build` logs are local reproduction pointers, not release artifacts.
