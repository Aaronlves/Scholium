# Scholium Editor Interaction Acceptance

**Evidence date:** 2026-07-16  
**Status:** Automated interaction safeguards pass; real assistive-technology and complete CJK IME acceptance remains open

This is an evidence ledger, not product or interface authority. The Product
Guide owns Scholium's meaning and feature boundaries, the Design Handbook owns
the interface and accessibility contract, and `EDITOR_ARCHITECTURE.md` owns the
subordinate editor implementation boundary.

## Baseline and environment

- Source revision: `4007067d4563dc5747530fd682f81ef9ccf8ca5c` plus a dirty working tree.
- The pre-existing skill cleanup and hermetic editor-toolchain changes were
  preserved. This interaction slice adds composition policy, accessibility
  semantics, recovery hardening, tests, and this ledger.
- Host: macOS 27.0 (`26A5378n`), Apple silicon.
- Toolchain: `/Applications/Xcode-beta.app/Contents/Developer`, Xcode 27.0
  (`27A5218g`), Swift 6.4, macOS 27.0 SDK.
- QA bundle: `/tmp/Scholium-QA.app`, bundle identifier `com.kbmanager.qa`,
  Debug-only, disposable fixtures and isolated home directories.
- Current input sources at preflight: ABC and Simplified Chinese Pinyin. The
  account did not have Traditional Chinese, Japanese, or Korean input sources
  installed.
- VoiceOver, Voice Control, and Dictation were not active at preflight.
- Exact-source fixture SHA-256:
  `5337090697f967464ba4f570f2630a5a5be16e4ac12d599d95e32c113decb163`.
- Semantic-parity fixture SHA-256:
  `854f607a3c71337d5f8684b94de7e3aa12ee83731460e4a1e8f1fb2eccd67724`.

## Automated evidence

| Layer | Result | Evidence and interpretation |
| --- | --- | --- |
| Pure TypeScript | Passed | Hermetic `npm ci`, typecheck, and 40 Vitest tests. Composition tests are explicitly synthetic bridge-policy evidence: unchanged requests release once and in order; changed generations and identities reject; cancellation releases safely. Accessibility tests prove one multiline textbox contract, active-construct descriptions, and restoration after consequential announcements. |
| Native WKWebView | Passed | `MarkdownEditorWebViewIntegrationTests` under the selected Xcode toolchain and `/tmp` scratch. It proves one editable textbox with no `aria-valuetext`, exact CRLF reconciliation, exact UTF-8 and UTF-16 preservation for decomposed/precomposed accents, ZWJ/skin-tone emoji, Arabic and Hebrew, selection restoration, dirty mirror recovery, generation continuity, and normal post-recovery mutation. |
| Isolated QA XCUITest | Passed | `testDirtyEditorBufferSurvivesTheQAFaultRoute` in `/tmp/Scholium-UITests/Logs/Test/Test-ScholiumUITests-2026.07.16_17-06-17-+0800.xcresult`. The explicit Debug/QA launch argument exposed an app-local command that posted the namespaced distributed notification; the focused session reloaded, retained the dirty buffer, left disk unchanged, restored editor reachability, and committed byte-exactly on Read. |
| Existing conflict/focus journeys | Previously passed; adjacent rerun pending | The existing disposable-fixture journeys cover dirty external-edit retention, Compare Changes, Return to Editing focus, menu command routing, and commit-before-Search. Composition-specific conflict deferral is code- and state-covered but still requires genuine IME observation. |
| Complete repository verifier | Passed | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./Tools/Scripts/verify.sh` passed the protected-skill checks, hermetic editor typecheck and 40 Vitest tests, byte-reproducible bundle verification, deterministic derived-state checks, Core/Application/App suites, workflow CLI, symbol graph, and Release build. The unqualified verifier inherits the machine's Command Line Tools selection and cannot load the required Xcode Swift macro plugins. |

The first QA fault attempt tried to post the distributed notification from the
sandboxed XCUITest runner and was correctly denied by macOS. The final design
keeps the receiver unchanged and exposes the sender only inside the Debug QA
bundle when `--scholium-editor-qa-faults` is present. No Release route is
compiled, and an ordinary Debug build cannot enable it without both the QA
bundle identity and explicit launch argument.

## Real macOS journey ledger

Automated event synthesis and `XCUIElement.typeText` do not satisfy the rows
below. A row is **Passed** only after direct observation with the named macOS
facility genuinely active.

| Journey | Status | Evidence or blocker |
| --- | --- | --- |
| VoiceOver plus Full Keyboard Access | Not run | Requires a dedicated session with both facilities enabled. Accessibility hierarchy inspection alone is insufficient. |
| Voice Control | Not run | Voice Control was inactive; spoken-name and conflict-action journeys remain required. |
| Dictation | Not run | Dictation was inactive; insertion, punctuation, paragraph, undo, and save evidence remains required. |
| Spelling and standard text services | Automated structure only | CodeMirror remains the single `spellcheck=true` contenteditable, and the native context menu begins with WebKit's inherited menu. Real correction, Look Up, Speech, Transformations, and installed Services journeys remain required. |
| Simplified Chinese Pinyin | Ready but not accepted | Input source is installed. Genuine marked-text, candidate, cancellation, reconversion, undo, conflict, and fault journeys were not completed in this run. |
| Traditional Chinese, Japanese, Korean | Blocked by account configuration | Required input sources were absent at preflight. Install them before the acceptance session and restore the original source list afterward. |
| Accents, combining sequences, emoji, Arabic/Hebrew | Automated exactness passed; manual cursor journey open | Raw UTF-8 and UTF-16 preservation and recovery pass in WKWebView. Dead-key, emoji picker, bidi visual-cursor, logical-selection, copy/paste, save, and reopen observation remains required. |
| Composition race with Format/mode | Synthetic policy passed; real IME open | Controls consume `MarkdownEditorContext.composing`; native Format, Insert, Add Comment, and mode actions disable. A queued request crosses one task boundary after `compositionend` and must still match identity, fingerprint, and generation. Genuine candidate-window observation remains required. |
| Conflict or termination during composition | Recovery safeguard passed; real IME open | Dirty mirror recovery and deferred conflict presentation are implemented. No claim is made that an OS candidate window survives WebKit termination; accepted source survival is the requirement. |

## Completion decision

Editor interaction acceptance is **not complete**. No critical or high source-
fidelity defect is known from the automated slice, and the QA fault defect was
resolved and retested. The release gate remains open until real VoiceOver,
Full Keyboard Access, Voice Control, Dictation, Simplified/Traditional Chinese,
Japanese, Korean, dead-key/emoji/bidi, composition-conflict, and composition-
termination journeys pass and are recorded here.
