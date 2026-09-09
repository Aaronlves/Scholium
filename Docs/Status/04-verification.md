# Implementation Status: Verification Evidence

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Dated proof and its limits.

## Agent knowledge-base tools, 2026-09-09

Integration: 1,388 tests (Core 360+3, Contracts 70, Application 165+1, App 789),
with two App structure assertions repaired and rechecked separately. The gate log retains its nonzero exit. Public symbols, Release build/CLI and
resources/docs/localization pass. Four task-introduced omissions are resolved.
Evidence: `.build/agent-knowledge-tools/completion-audit.md`; Xcode 27 beta
27A5218g, Swift 6.4/SDK 27; `d75bceac` plus uncommitted changes.
Native focus/menu/IME/VoiceOver/adaptation and real Zotero/provider acceptance
remain open; no release acceptance is implied.

## Current verification snapshot

**2026-09-09 — Chat:** 21 content/reader checks, Debug build/docs/localization pass.
QA verifies viewed changes, history/comparison resizing, table scrolling,
content-fitted previews and Escape: `.build/chat-content-acceptance.md`.
Earlier integration remains nonzero; `.build/chat-research-acceptance.md` records prior Release proof. Release, VoiceOver, adaptation and Zotero acceptance remain open.

**2026-09-09 — selection shortcuts:** 31 native and 234 editor checks pass.
Signed-in QA verifies exact capture, Polish, Adopt and one-step Undo; menu/settings/recovery inspected. Full App integration remained red. Human adaptation
and scholarly acceptance remain open. Evidence: `.build/agent-chat-evolution/selection-*`.

**2026-09-08 — unified public transcript:** Shared typed decoding validates full
history atomically and accepts lifecycle-only metadata without inventing messages.
Eighty-seven checks, build/localization and live restoration/send/Copy pass without
replay. All 500 Notes remain unchanged; QA is removed with login retained. The
scroll-coordinator correction passes 11 architecture and 230 editor checks.
Evidence: `.build/agent-chat-evolution/transcript-*`, `scroll-owner-*`; no whole-app gate.

**2026-09-08 — activity and connection renewal:** Sixty-eight checks cover
independent tool outcomes, expired approvals, root initialization, failure,
cancellation and no replay. Live `/bin/sleep 120` outlives its reply; settings
wait with Send disabled until actual command exit, then renew without losing
thread/draft/login. Earlier disabled-to-live renewal records webpage Sources and
honest JavaScript-body unavailability. All 500 Notes remain unchanged; QA is
quit/removed with authentication retained. Build/localization/docs pass. Evidence:
`.build/agent-chat-evolution/lifecycle-*`, `search-renewal-*`. Live method-root
restoration, delegated waiting, provider search semantics and full adaptation
remain open. Unsubscribe alone leaves threads loaded.

**2026-09-08 — mouse selection handoff:** In the signed-in isolated QA window,
native triple-click selects a complete Edit paragraph and the floating Ask Agent
action stages exactly the bytes obtained through native Copy, including its final
newline. Source triple-click, floating action, attachment locator, source return
and native Copy also agree after navigation acknowledgement. Neither route sends
a message. All 500 fixture Notes remain byte-unchanged, both staged attachments
are removed and QA is quit. Evidence: `.build/agent-chat-evolution/pointer-*`.
Computer Use drag did not establish a selection; Edit AX selected-text reporting
differs from visible selection and native Copy. These paths do not certify drag
or assistive-technology correctness. Current catalog references expose stable
IDs only for resolved, editable Notes; the read-only fallback notice therefore
has no ordinary entry route, and identity-transition behavior remains unverified.
Two native WebKit checks additionally verify that Chat source return produces
the exact DOM selection and source snapshot across Edit/Source with BOM, CRLF,
CJK and emoji; stale revisions preserve selection and focus. Evidence:
`.build/agent-chat-evolution/selection-native-return-tests.log`. In-process AppKit
accessibility traversal exposes only the WKWebView group, not its remote text
nodes. It therefore cannot resolve the observed AX-description discrepancy;
no accessibility workaround or additional source-selection owner was introduced.

**2026-09-08 — document-bound, revision-checked navigation:** Replaced independent
pending line/range/exact-selection fields with one `DocumentSourceLocationRequest`
owned by `DocumentController`. Every activation carries its destination and new
identity; document changes and closing the last tab invalidate it, and stale
acknowledgements cannot consume a replacement. Thirteen owning document/Review/
Chat checks and two adjacent window-composition checks pass. Requests carry the
checked source revision through application; the editor maps original CRLF and
Unicode offsets through its existing exact-source map and generation-checked
bridge. Thirteen focused checks pass with Review/editor revision rejection,
unchanged source and selection, and native keyboard focus transferred from a
separate input. An additional rejection check preserves that input's focus.
Live QA verifies repeated Review activation and exact native Copy after CRLF
passage return from Chat in Edit and Source. All 500 fixture Notes are restored
byte-exact and the unsent test attachment is removed. Build, localization and
documentation validation pass. Evidence: `.build/agent-chat-evolution/navigation-*`.
Revision-change rejection is deterministic WebKit evidence, not a timed live
filesystem race. Read-only notice and full accessibility journeys remain open.

**2026-09-08 — exact Chat passage return in Review:** Review now restores the
verified native selection rather than consuming only its line. A bounded DOM
candidate must match the exact source block before selection; a changed candidate
or unrendered syntax cannot choose a similar occurrence. Editable unrepresentable
ranges open Source through the existing mode owner. Five focused checks pass,
including real WebKit repeated Unicode text, unrendered Markdown rejection,
ordinary arrival preservation and versioned navigation. The final focus change
also passes its owning WebKit check; 229 WebEditor checks and the QA build pass.
Live QA opens the retained Review attachment, selects exactly its original text
without the trailing punctuation, and copies it directly with native focus.
A whole-source Edit capture opened from Review switches to Source and copies
all 445 original bytes exactly. All 500 fixture Notes remain unchanged and test
drafts are cleared. Evidence: `.build/agent-chat-evolution/review-range-*`.
The read-only unavailable-selection notice and full IME/assistive-technology
acceptance remain unverified in the live window; no whole-app gate is claimed.

**2026-09-08 — recovery limits and native input sizing:** Three owning recovery
checks pass, including three exhausted automatic launches, retained uncertain
input/offline draft, and explicit reconnect without a new runtime turn. Forced
termination of the verified idle QA app (without normal shutdown) preserved an
already-persisted draft, exact Note attachment, history, login and preferences;
its runtime child exited and the reopened app did not send input. This does not
prove power-loss durability or recovery during a source transaction.
The journey exposed live composer geometry being mutated by sizing probes. A
regression first fails on that mutation; eight native-input checks now pass with
read-only measurement. Live QA verifies direct accessibility clicks before/after
multiline growth, narrow-sidebar CJK/English/emoji wrapping and native Undo. All
temporary drafts were cleared. Evidence: `.build/agent-chat-evolution/recovery-*`,
`crash-*` and `composer-measurement-*`; no whole-app gate is claimed.

**2026-09-08 — additional input and background continuity:** Two regression
checks first reproduced silent new-turn dispatch after the original turn ended
during preparation, and acceptance of a mismatched steering acknowledgement.
Input now retains its original turn and send identity; the 34 owning conversation,
delegation and child checks pass. A real GPT-5.6-Luna turn accepted an additional
scope reduction under the same turn ID and completed while another conversation
remained visible with an independent unsent draft. The model correctly reported
that the query returned only one Note rather than inventing the requested three.
Terminating only the verified idle QA App Server child triggered automatic
reconnection with a new child PID, no login prompt, unchanged messages/drafts and
no input replay. The 500 fixture Notes remain byte-identical. Build, localization
and documentation validation pass; logs/public evidence are retained under
`.build/agent-chat-evolution/input-*`. This proves the bounded live path, not
prolonged offline, abrupt application exit or full accessibility acceptance.

**2026-09-08 — reply Sources provenance:** Successful scoped Note reads retain
their exact revision, returned line ranges and bounded UTF-8 excerpts. The 37
focused App checks and one runtime-observation check pass, covering disjoint
coverage, changed revisions, reply/turn ordering, failed or wrong-origin reads,
material representations and structured web access. Build, localization and
documentation validation pass. Real GPT-5.6-Luna QA displays a confirmed 18-line
Note read, opens its versioned line reference and retains evidence after restart.
Older replies correctly show unrecorded coverage and separate supplied materials.
A new Live-search conversation records a real webpage open; the page exposes
only its title/JavaScript requirement, and both the reply and Sources retain that
limit without claiming full-text reading. Public evidence is in
`.build/agent-chat-evolution/sources-*-public.json` and owning logs. All 500 fixture
Notes remain byte-identical. Full provider/PDF input, physical accessibility and
adaptation acceptance remain open; this is no whole-app or release-gate claim.

**2026-09-08 — Selection Actions and Chat handoff:** The native shared floating
surface now presents Ask Agent from Review/Edit/Source selections. The bounded
live QA journey verifies Review pointer capture, draft preservation, native
composer focus, no sidebar toggle when Chat is already visible, a real
GPT-5.6-Luna read-only reply, Source excerpt preview/exact-range return, first
Escape preserving selection, and light/dark control presentation. All 500 fixture
Notes remain byte-identical to the baseline; normal restarts retain the isolated
login and Full Access. The 48 focused App checks and 229 WebEditor checks pass;
the QA app builds with Xcode 27 beta. Evidence is in
`.build/agent-chat-evolution/selection-*.log` and `selection-live-progress.json`.
Review capture maps source-identical blocks only; exact return and Source fallback
are verified above. Formatted/synthesized captures use Edit/Source. Computer Use Edit/Source drag
and Edit AX source-selection agreement remain open as recorded in Open Work.
No complete integration gate or physical accessibility acceptance is claimed;
the shared checkout contains unrelated work. One QA instance remains available
within the ongoing researcher feedback session, with no active turn or test draft.


**2026-09-08 — retired Action cleanup:** The 187 owning and 46 adjacent
checks pass for removal of managed assessment/Analyze paths and ordinary Works
file operations; orphan bytes remain unchanged. Documentation, localization and
bundled Core Protocol checks pass. Full verification and an adjacent architecture
assertion stop at the existing AgentChatController I/O allowlist mismatch.
Evidence: `.build/action-cleanup/`; no complete gate or GUI acceptance.

**2026-09-08 — native sidebar layout cleanup:** Sidebar-owned container/content
insets replace the old Library aliases into the peripheral editorial grid. The
header label owns a wider full hit region and native typography; plain Buttons
and Menus use one system secondary-label role with inherited tint reset. The
custom header pointer/press painter and active-state parameter are removed.
A disposable identical-symbol comparison exposed the borderless menu rendering
difference before choosing the native plain path; all probe code was removed.
The workspace navigator uses AppKit `fillEqually`, replacing manual per-segment
widths that added to native chrome and overflowed the visual container edge.

The final 98 owning presentation/architecture checks pass. QA at a 300-point
sidebar covers light/dark Chat list/detail, aligned text/container tracks,
full-row whitespace activation, the enlarged archive-menu hit region, native
menu open/Escape, selected-mode disabled controls and cancellation. The corrected
navigator and Search edges were visually checked in dark mode. Existing QA
conversations remain available; the QA is retained for feedback. An attempted
wider-sidebar drag did not change the divider, so it is not wider-layout proof.
The compose symbol subsequently received a body-scaled half-point drawing
correction left/up within the unchanged header hit area. Symbol and screenshot
bounds informed this correction; dark QA checked its pairing with archive and
ellipsis. The 98 owning checks pass in `sidebar-optical-tests.log`.
Full VoiceOver, increased contrast/transparency/motion adaptation and whole-app
acceptance remain open. Evidence: `.build/chat-refinement/native-sidebar-tests.log`,
`native-sidebar-build.log`, `native-sidebar-qa.log` and Computer Use observations.

This is a record of reported execution on the named dates, not proof that a
later worktree passes. Test counts overlap and must not be summed. Logs are
local reproduction pointers, not release artifacts. Current capabilities belong
to the reachable chapters and outstanding acceptance to Open Work.

### Chat and current whole-app boundary — 2026-09-07–08

- **Signed-in research loop and floating Chat, 2026-09-08:** Xcode 27 beta
  Debug QA used the standard disposable 500-Note Triptych, independently signed-in
  official Codex 0.153.4 and GPT-6-Astra. Search and complete reading of QA Topic,
  QA Work and 示例材料 succeeded. A second turn reused the connection, reached
  runtime MCP approval and the current-source Note approval, and changed only
  the requested sentence in QA Topic. The native comparison displayed that exact
  replacement; confirmed Undo restored all 500 Notes to their starting bytes.
  This closes CHAT-LIVE-01 and CHAT-LIVE-02 for this bounded live path. Earlier
  failure diagnostics remain in `real-loop-runtime-diagnostics.json`.
  Normal app restarts restored login, history and the researcher's subsequently
  selected Full Access setting without another sign-in or automatic resend. A
  post-restart tool read verified the restored sentence. A separate read-only
  turn was stopped through the UI; runtime `turn_aborted` and retained interrupted
  state agree, with no pending input. The approved write occurred before switching
  the QA conversation to Full Access; no global permission default was changed.
  Evidence is under `.build/agent-chat-evolution/real-loop-retest-*.json`.

  Computer Use visually checked compact reply files, their operation-history
  popover, transcript content passing beneath floating native material, pointer
  and keyboard Note completion, exact copied reply text/links, and a Sources
  popover containing both a Note and a supplied webpage. Reconciled runtime phase
  metadata separated public process from final text; completed process collapsed
  and reopening retained individual tool calls. The neutral latest arrow replaces
  the labelled Accent button; bottom-distance and composer-clearance calculations
  were corrected. Sources opens beside its control, and its typography resets
  inherited footer styling. Light/dark component renders were inspected in
  `renders/reply-surfaces-*.png`; they do not prove physical adaptation or motion.
  The final focused integration passed eight Application and 61 App checks in
  `chat-delivery-tests.log`; 23 presentation/input checks passed in
  `reply-final-input-tests.log`. Localization and documentation validation pass.
  The final Xcode Debug build passed in `reply-final-build.log`. UI-control transport
  intermittently disconnected independently of Scholium. Some native input AX
  clicks required coordinate fallback. Full Keyboard Access, VoiceOver, installed
  IME, complete adaptation and whole-app integration remain separate open gates.

- **Source reference revisions, 2026-09-08:** answer links and attachment opening
  share the window's existing document transition queue. Links carry exact-source
  SHA-256 and known vault identity; only a verified current revision and valid
  line publish a passage location. Changed/unversioned/unverifiable locations
  open the exact Note with an informational notice. Same-Note reference opening
  retains its editor without saving or reconstructing it. Twenty-two owning
  reference, material, presentation and transition checks pass in
  `.build/agent-chat-evolution/reference-navigation-tests.log`, including BOM/CRLF,
  external file changes, malformed URLs, wrong identities, stale attachments,
  exact provider-input URLs and preservation of unsaved source. Documentation
  and localization validation pass. This is deterministic fixture evidence;
  live source-link selection, composition and signed-in provider acceptance
  remain open. No complete repository gate was rerun for this slice.

- **Image drag and capture provenance, 2026-09-08:** the message editor now
  accepts image copy-drops through native dragging callbacks. File references
  retain precedence; drag entry reads only types, and accepted drops capture
  immutable bytes through the same material preparation as Paste. Five Application
  and 44 App checks passed in `image-drop-final-tests.log`, including delayed
  pasteboard data, copy-only admission, disabled/marked-text refusal, exact draft
  selection and working text Undo, image delivery, source round trips, branching
  and archive refusal. Archive 11 retains runtime timing and typed file or
  image-capture source; version 9 remains unchanged and nonauthorizing. Light/dark
  dropped-image detail renders were visually inspected under `renders/`; these
  are offscreen component evidence, not physical cross-app dragging or human
  input/adaptation acceptance. Localization and documentation validation pass.
  Logs are under `.build/agent-chat-evolution/`. No live provider inference or
  complete repository gate was run for this slice; the prior integration failures
  remain the whole-app boundary.

- **Nested Agent navigation, 2026-09-08:** reports in child history now use one
  native navigation stack, retaining the original conversation scope. Thirty-two
  owning child/delegation/presentation/architecture checks passed in
  `nested-agent-final-tests.log`. They cover arbitrary-target rejection, nested
  ancestry, independent drafts and parent receipts, unrelated targets, cancellation
  and old-connection exclusion. Disposable 500-Note QA exercised Back, revisiting
  an existing path target, reopening retained drafts after app restart, unavailable
  destinations, original-parent navigation, Done and Escape during a pending read.
  Light/dark screenshots were visually inspected; native Back tint was corrected
  at the sheet boundary, and loading no longer implies parent unavailability.
  The final Xcode 27 beta build passed; `nested-agent-source-proof.json` confirms
  all 500 Markdown files remained byte-identical. QA was quit and its app, fixture
  copy and isolated state removed. Logs are under `.build/agent-chat-evolution/`;
  screenshots and accessibility observations remain in the task transcript.
  This is fixture-runtime Computer Use evidence, not human accessibility/IME,
  complete adaptation, motion-performance or real-provider acceptance. The separate
  official-runtime readiness probe returned no account and required authentication
  in an isolated configuration (`provider-readiness.json`); it started no inference.

- **Chat architecture cutover, 2026-09-08:** question, approval, child-history
  and PDF-range failure values now belong to Contracts. Application retains
  runtime decoding, ancestry checks and exact approval-response encoding; the
  App retains presentation and three explicit composition roots. No archive
  schema or conversation state owner changed. Tool forms retain a revision and
  read-only warning projection; stale configuration still rejects saving.
  Forty owning checks passed in `chat-boundary-owning-tests.log`, including
  approval scope, child pagination, stale tool forms and strict import ownership.
  The complete verifier passed 342 Core, three performance, 63 Contracts, 150
  Application and one architecture-measurement checks. Its 719-test App run
  reported 24 issues, including five Chat color/presentation inventory issues.
  Those five were corrected using the existing native secondary-label role and
  exact reviewed control inventories; all 101 architecture and presentation
  checks then passed in `chat-boundary-presentation-tests.log`. The remaining
  document lifecycle, editor contract/projection and WebKit localization
  failures keep whole-app acceptance open. The complete verifier was not rerun
  after these scoped corrections. This closes the ten-file Chat import failure
  recorded below, not real-provider or full UI acceptance. Logs are under
  `.build/agent-chat-evolution/`, including `chat-boundary-integration-gate.log`.

- **Native Chat cards and tabs, 2026-09-08:** specification-first presentation
  changes reuse system GroupBox and macOS grouped TabView. Twenty-two owning
  interaction/render checks passed in `native-cards-final-tests.log`; thirty
  Chat/approval/question regression checks passed in `native-cards-approval-final.log`
  after the same card grouping was applied to ordinary Note approvals. Localization
  passed in `native-cards-localization.log`. The Xcode-selected SwiftPM Debug QA
  bundle was built in `native-cards-qa-build.log` and incrementally rebuilt in
  `native-cards-qa-final-build.log`. Computer Use operated only the isolated
  500-note Triptych copy with the synthetic runtime: opened Agent detail, pasted
  a Chinese draft, switched Activity/Details while retaining draft/focus, sent
  to the parent and observed its receipt, opened both usage tabs, selected and
  skipped a question, and checked actual light/dark windows. Final checks
  confirmed translated Agent labels, named usage metrics and system quota tint.
  Native grouped tabs produced invalid offscreen glass bitmaps; actual QA
  screenshots showed correct rendering, so the bitmap artifacts are not treated
  as visual passes. Runtime motion feel/performance, installed IME, human
  accessibility and full adaptation remain unaccepted. Evidence/logs are under
  `.build/agent-chat-evolution/`; Computer Use observations are retained in the
  task transcript. The subsequent architecture cutover above closes the import
  failure; the signed-in provider journey remains open. The QA process was quit and its
  generated bundle, fixture copy and isolated home were removed after inspection.

- **Parent-mediated child adjustments, 2026-09-08:** eighteen owning interaction,
  branch/search/material/method and render checks passed in
  `child-coordination-tests.log`. They cover exact target ancestry before
  admission, ordinary parent-draft/material/method isolation, independent visible
  selection, exact current-turn steering and new parent turns, parent receipts,
  retained unknown delivery without replay, closing after admission, archive
  exclusion, persistence and explicit target removal in an edited branch.
  The broader `child-coordination-final-tests.log` has fifty passing checks and
  one failing architecture import check: ten Chat files import Application
  outside its composition-root allowlist. The subsequent cutover above closes
  that failure; this earlier run was not an architecture or complete integration
  pass. Light/dark detail images cover
  composition, parent receipt, unavailable and disconnected states; the narrow
  edited-branch render shows the original-target restriction. Images were
  inspected offscreen using never-ordered native windows.
  Final render validation passed in `child-coordination-render-final.log` after
  correcting dark-mode target text with system semantic label colors.
  Localization passed in `child-coordination-localization.log`. No UI automation or real-provider
  child delivery was exercised; direct input and scoped child authority remain
  separate open work. Evidence is under `.build/agent-chat-evolution/`.

- **Child Agent inspection/interruption, 2026-09-08:** two Application ancestry/
  pagination checks and thirteen App interaction/delegation/render checks passed
  in `child-inspection-final-tests.log`. They cover nested and cyclic/unrelated
  ancestry, complete page order, private-reasoning exclusion, exact request text
  with separately labelled nontext material, runtime-only managed-tool reports,
  cancellation and stale-turn rejection. Interruption is sent to the child's
  exact observed turn and remains unconfirmed until a read proves its end;
  parent execution/token and visible conversation remain unchanged. The final
  presentation/architecture run passed 102 App checks in
  `child-inspection-presentation-final.log`. Native detail images cover active,
  pending interruption, unavailable and disconnected states in light/dark.
  Eleven native/interaction checks passed in `child-inspection-native-final.log`;
  final normal/error images were inspected with a never-ordered native window
  supplying button appearance. App-authored failures now retain typed meaning
  until localized by the view; runtime error text remains verbatim.
  Localization passed in `child-inspection-localization-final.log`. Evidence
  is beneath `.build/agent-chat-evolution/`. These are protocol fixtures and
  offscreen native renders, not live official child execution, sheet keyboard/
  focus or human accessibility acceptance. No UI automation was used; direct
  child messaging and approval/admission integration remain open.
  The matching published
  [0.153.4 interruption source](https://raw.githubusercontent.com/openai/codex/rust-v0.153.4/codex-rs/app-server/src/request_processors/turn_processor.rs)
  checks a supplied nonempty turn ID against an available active-turn snapshot
  and defers its reply until interruption handling. This is source evidence,
  not live-child subscription/turn-state acceptance. Its
  [direct-input policy](https://raw.githubusercontent.com/openai/codex/rust-v0.153.4/codex-rs/app-server/src/request_processors/thread_input.rs)
  rejects direct input to multi-agent v2 spawned threads; the installed schema
  reports `canAcceptDirectInput` for clients to honor.

- **Background Chat notifications, 2026-09-08:** 25 protocol/controller and
  notification-service checks passed in `chat-notification-tests.log`; seventeen
  routing/render checks passed in `chat-notification-routing-tests.log`. They
  cover completion/failure/input, duplicate suppression, independent conversations,
  coalescing, validity before/after system authorization, cold archived-history
  opening and missing targets. A disposable window-model fixture preserved the
  open Note, unsaved source and unrelated draft. Twenty-eight native/composer
  checks passed in `chat-notification-native-final.log`. The final owning and
  presentation/architecture run passed 114 checks in `chat-notification-final-tests.log`,
  including scoped App Note approval alerts without exposing proposed source.
  Twelve shared-policy checks passed in `chat-notification-shared-policy.log`,
  explicitly covering foreground Chat suppression and one authorization request
  shared by concurrent Note and Chat events.
  Narrow light/dark notification destinations were inspected; a never-ordered
  native window supplied the hybrid composer's appearance context. The final
  placeholder render passed in `chat-notification-placeholder-render.log` and
  its dark appearance was inspected. Localization passed in
  `chat-notification-localization-final.log`. Evidence is beneath
  `.build/agent-chat-evolution/`. Notification tests use a fake transport: no
  macOS permission prompt, banner delivery or UI automation was exercised.
  Actual system authorization, banner clicks, cold launch and live provider
  acceptance remain open.

- **Delegation observations, 2026-09-08:** two Application projection checks
  and fourteen App interaction/branch/render checks passed in
  `delegation-final-tests.log`. They distinguish coordination completion from
  independently reported target states and preserve exact requests/results,
  sender identities, search passages, Stop, storage, branching and reconnect.
  Malformed reports remain visibly uncertain without a receipt or child admission.
  The presentation/architecture run passed 101 App checks in
  `delegation-presentation-final.log`. Narrow light/dark native reports were
  inspected; shared status localization now uses the existing locale-aware owner.
  Final identity checks passed in `delegation-identity-final.log`, including a
  list report that contains its own issuing Agent. The final startup label render
  passed in `delegation-label-render.log` and was inspected to distinguish starting
  an Agent from completing its work.
  Localization passed in `delegation-localization-final.log`. All evidence is
  under `.build/agent-chat-evolution/`; no UI automation or provider inference was
  used. This covers public observations, not direct child execution controls or
  live provider/human acceptance.

- **Runtime approvals and tool input, 2026-09-08:** strict Application projections
  and App interaction checks passed in `runtime-approval-metadata-tests.log`,
  including the installed official Codex 0.153.4 metadata-capability handshake,
  account/model queries and thread creation without inference. Forty-two App
  regression checks passed in `runtime-approval-admission-final.log`; ten focused
  approval/question checks passed in `runtime-approval-secret-final.log`. They
  cover exact grant scope, delayed resolution, stale/duplicate request identity,
  immediate admission revocation, tool identity/Stop and secret option/answer
  exclusion from storage. Twenty-six interaction/render/presentation checks passed
  in `runtime-approval-visual-final.log`. Native command, permission, file and
  submitted approval images plus network and tool-input forms were inspected in
  light/dark variants; localization passed in `runtime-approval-localization-final.log`.
  Logs and renders are beneath `.build/agent-chat-evolution/`. Offscreen rendering
  used no UI automation. Actual provider authorization/execution, persistent
  policy amendments and live keyboard/focus/accessibility acceptance remain open.

- **Proposed Note comparison, 2026-09-08:** 24 App/router checks passed in
  `.build/agent-chat-evolution/update-preview-admission-tests.log`. Real
  Application/file operations verified no preview editor flush or source write,
  no preview change record, BOM/CRLF and source-mode preparation, equality with
  the eventual write fingerprint, decline preservation and external-revision
  rejection after Allow Once. Thirty-five router/Chat/comparison/presentation
  checks passed in `update-preview-final-tests.log`. Light/dark exact-comparison
  sheets were inspected; the shared comparison's labels now use its correct
  localization bundle. Localization passed in `update-preview-localization-final.log`.
  The additional stopped-preview check passed in `update-preview-stop-test.log`;
  resuming a suspended preview after Stop produced no approval or write.
  No UI automation or provider inference was used. Native sheet keyboard/focus,
  full adaptation, VoiceOver and the signed-in research journey remain open.

- **Research questions, 2026-09-08:** one strict parsing check and three App
  interaction checks passed in `.build/agent-chat-evolution/questions-tests.log`.
  Fixture requests covered malformed sets, unlisted answers, conversation
  switching, delayed confirmation, secret exclusion from saved history, Skip
  and Stop without answer replay. Nineteen App interaction/render/presentation
  checks passed in `questions-render-final.log`. Native light/dark unselected,
  custom-answer and submitted forms were inspected; the final forms use the
  correct localization bundle and readable submitted answers. Localization
  passed in `questions-localization-final.log`. These are offscreen native
  renders and protocol fixtures, not provider, physical keyboard/IME, VoiceOver
  or live-window acceptance. No UI automation was used.
  The adjacent regression passed three Application checks and 37 App checks in
  `questions-final-regression.log`.

- **Edit in New Branch, 2026-09-08:** two projection/confirmation checks and
  twenty App branch/material/method/presentation checks passed in
  `.build/agent-chat-evolution/edit-branch-final-tests.log`. Fixture execution
  verified first-turn empty history, later-turn exclusion, exact draft material
  and method retention, no automatic send, source preservation, additional-input
  exclusion and wrong-prefix rejection. The installed runtime schema declares
  `beforeTurnId`; live official-runtime execution and native menu/focus acceptance
  remain open. Localization passed in `edit-branch-localization.log`. The adjacent
  clipboard regression passed 44 App checks in `clipboard-final-regression.log`.
  No UI automation was used.

- **Clipboard images, 2026-09-08:** five store checks and four native-input
  checks passed in `.build/agent-chat-evolution/clipboard-material-tests.log`.
  TIFF orientation normalization, exact captured encoding, PNG byte retention
  and disposal were exercised with ImageIO. Private pasteboards verified file
  precedence and unchanged text/selection; marked text retained its native path.
  Five store checks and eleven App delivery/search/input/render checks passed in
  `clipboard-material-delivery-tests.log`. Fixture sending included the captured
  image and clipboard provenance. Light/dark details were visually inspected;
  localization passed in `clipboard-material-localization.log`. No general
  clipboard content or UI automation was used. Physical Paste, text Undo,
  installed IME, Quick Look and provider interpretation remain unaccepted.

- **PDF page images, 2026-09-08:** four store/parser checks and 40 Chat,
  material/branch and presentation checks passed in
  `.build/agent-chat-evolution/pdf-page-final-tests.log`. Real PDFKit rendered
  selected pages from retained bytes; fixture delivery paired each PNG with its
  physical page label. Coverage includes scanned input, range rejection,
  cancellation before attachment, exact conversation ownership, derivative
  fingerprint rejection and cleanup while preserving the original PDF.
  Four store checks plus five native render/style/delivery checks passed in
  `pdf-page-render-tests.log`; light/dark normal/error forms and a generated page
  were visually inspected. Localization passed in `pdf-page-localization.log`.
  These are native rendering and protocol-fixture observations, not provider
  vision interpretation, live sheet/IME, Quick Look or human acceptance. No UI
  automation was used.

- **Local file materials, 2026-09-08:** three file-store checks and 39 Chat,
  material, branch and native presentation checks passed in
  `.build/agent-chat-evolution/local-material-regression-tests.log`. Real
  Foundation/PDFKit/ImageIO operations captured files and page text; fixture
  runtime delivery received a staged image path with exact original bytes.
  Coverage includes BOM/CRLF fidelity, external source changes, missing/oversized
  input, partial PDF text, cancellation before admission, unavailable copies,
  retained drafts and per-conversation ownership. Material records survive
  history saving. Two offscreen/delivery checks plus the three store checks
  passed in `local-material-final-tests.log`; light/dark PDF text and no-text
  detail renders were inspected. Localization passed in
  `local-material-localization.log`. No UI automation or provider inference
  was used. Native file selection/paste/drop, image thumbnails, Quick Look and
  provider image/PDF-discussion acceptance remain open.

- **Whole-Note materials, 2026-09-08:** 15 owning/presentation checks passed in
  `.build/agent-chat-evolution/note-material-owning-tests.log`. A disposable
  workspace exercised the actual window document-read and Chat attachment path,
  then fixture runtime sending. BOM, CRLF, YAML and Unicode stayed exact;
  switching conversations did not redirect the material. An unavailable dirty
  editor rejected capture without changing its buffer or substituting disk text.
  Unsupported schema-2 archives remained unchanged. The earlier 25 Chat/branch/
  search checks passed in `note-material-tests.log`. Ten native presentation,
  color/typography and render checks passed in `note-material-render-tests.log`;
  populated and empty Note-picker images were visually inspected in both
  appearances. Native List rendering used test-owned, never-ordered windows;
  No UI automation. Localization passed in `note-material-localization.log`.
  This does not establish actual live editor capture, physical picker interaction,
  VoiceOver, signed-in inference or complete file/image material support.

- **Tool configuration, 2026-09-08:** six owning and offscreen checks passed in
  `.build/agent-chat-evolution/tool-environment-tests.log`. The installed official
  runtime applied version-checked writes, rejected stale revisions, handled quoted
  names and removal, discovered a real offline fixture server and reported its
  subsequent disabled state. That server required a synthetic variable loaded
  from the isolated runtime's own environment file; no inherited-environment
  filtering was relaxed. Bearer-variable addition/removal also passed runtime
  readback without contacting a remote provider. Fixture checks cover retained
  stale forms, explicit reload, active-execution exclusion and disconnect;
  projection checks protect untouched access fields and structured environment
  references. Light/dark native remote/local form images were inspected before
  and after adding Advanced access controls. No UI automation, private credentials,
  signed-in inference or live sheet/keyboard/VoiceOver acceptance was used.
  Nine adjacent method, authentication and native-style checks passed in
  `tool-config-adjacent-tests.log`; localization validation passed in
  `tool-environment-localization.log`. This does not close the whole-app gate.

- **Tool authentication, 2026-09-08:** three owning checks passed in
  `.build/agent-chat-evolution/tool-auth-running-tests.log`: secure URL validation
  and fixture lifecycle checks cover active-conversation login, failure/retry,
  exact tool/thread completion, absent URL persistence and disconnected requests.
  The installed runtime schemas establish the request/notification shape;
  no real external-provider login or credential entry was performed. Four native
  presentation/style checks passed in `tool-auth-render-tests.log`. Offscreen
  ready and pending-authentication Settings images were visually inspected;
  localization validation passed in `tool-auth-localization.log`. Browser opening,
  shared confirmation and VoiceOver remain live acceptance gaps. No UI automation
  was used, and a prepared sign-in URL is not reported as a successful login.

- **Local method association, 2026-09-08:** eight owning/presentation checks
  passed in `.build/agent-chat-evolution/association-final-tests.log`, covering
  association/removal, scope and reconnect, failed application without background
  retry, shared-preference merging, method lifecycle and native style ownership.
  The updated directory validation and recovery checks plus installed-runtime
  association/withdrawal passed in `association-recovery-tests.log`. The official
  runtime changed discovery without modifying the synthetic Skill file; no model
  inference was used. The official check also passed both a direct Skill folder
  and a collection containing nested Skill folders (`association-directory-shapes.log`).
  Light/dark native offscreen Settings renders were visually
  inspected, and localization validation passed in `association-localization.log`.
  No UI automation was used. Real folder-picker, focus and VoiceOver acceptance
  remain open; this is not external tool authentication or complete Chat acceptance.

- **Methods and tool inventory, 2026-09-08:** four owning checks passed in
  `.build/agent-chat-evolution/methods-owning-tests.log`, including the installed
  official runtime discovering and toggling a synthetic method in an isolated
  configuration without model inference. The installed-runtime check also passed
  MCP inventory discovery in `methods-official-runtime.log`, without an
  authenticated external tool call. Fixture checks cover retained choices,
  explicit Skill input, disabled/missing-method Send exclusion and disconnect.
  Three native style-ownership checks plus an offscreen-render check passed in
  `methods-presentation-tests.log`. After moving appearance refresh to the
  connection Settings owner, the lifecycle and render checks passed in
  `methods-final-tests.log`; light/dark populated Settings images were visually
  inspected. Localization validation passed in `methods-localization.log`.
  This does not establish real Skill execution, external tool setup/authentication
  or live focus/confirmation/VoiceOver acceptance. No UI automation was used.

- **Conversation branches, 2026-09-08:** 30 owning checks passed across branch
  projection, native controller, Chat regressions and presentation in
  `.build/agent-chat-evolution/branch-owning-tests.log`. Four targeted checks
  passed after adding archived-source cancellation in `branch-final-tests.log`.
  Those four checks also passed when the runtime omitted user `clientId`, using
  the correlated turn-start response for identity (`branch-identity-tests.log`).
  One opt-in offscreen native list render passed in `branch-render.log`; the
  light/dark images with a created branch were visually inspected.
  Localization validation passed in `branch-localization.log`. Runtime schemas
  were generated from the installed official executable; these tests exercised
  the deterministic fixture, not signed-in provider inference or official
  history forking. No UI automation was used; live menus and focus remain open.

- **Conversation retrieval, 2026-09-08:** 15 focused checks passed for public
  Unicode/literal matching, excerpts, streaming-stable Find navigation, captured
  rename ownership, marked-text command exclusion and presentation, including
  three opt-in offscreen render checks. Light/dark list and 280pt Find controls
  were visually inspected. Logs: `agent-chat-evolution/search-final-tests.log`
  and `search-localization.log` beneath `.build/`; localization validation passed.
  Both typography/color ownership checks passed in `search-design-boundary.log`.
  This does not establish live scrolling/focus, installed IME or VoiceOver
  acceptance. No UI automation or signed-in inference was used.

- **Concurrent Chat cutover, 2026-09-08:** 42 focused checks passed across Chat,
  capabilities and presentation. Four real authenticated-socket checks cover
  independent peers while one waits, bounded shutdown with an uncooperative
  admitted operation, slow operations and endpoint reuse. After adding listener
  drain tracking, those four checks and two offscreen-render checks passed in
  `agent-chat-evolution/concurrency-renders.log`. Light/dark list images were
  visually inspected. A complete `verify.sh` attempt passed static/resource
  validation, 342 Core plus three performance checks, 63 Contracts checks and
  127 Application plus architecture measurement checks. The 658-test App run
  reported 18 issues across eight tests: document scroll restoration, editor
  contract assertions, pointer selection/font scaling, math bridge reconstruction
  and WebKit localization expectations. Chat/bridge checks passed; the gate
  stopped before release build/CLI checks. Log:
  `.build/agent-chat-evolution/integration-gate.log`. This is not a passing gate
  or signed-in runtime/human acceptance; No UI automation.

- **Runtime capability slice, 2026-09-08:** owning Chat, capability decoding,
  presentation and native input checks passed, including per-conversation
  preferences, configured-default reset, plan/usage retention and interruption
  during compaction. An isolated installed-runtime smoke exercised the typed
  paginated model catalog, configuration read and thread creation without
  inference. The broader focused run exposed existing frontend executable I/O;
  moving it to Application passed all 10 architecture-boundary checks plus the
  automatic-connection regression. Logs: `.build/agent-chat-evolution/owning-tests.log`
  and `architecture-tests.log`. Localization and documentation validators passed.
  Offscreen AppKit-hosted light/dark renders of runtime controls were visually
  inspected under `renders/`; they establish component appearance only. No UI
  automation or real research data was used. Live layout/focus/adaptation,
  installed IME, signed-in inference and the complete integration gate remain open.

- **2026-09-08:** 136 owning checks passed for connection discovery, archive/
  restore, archived send exclusion, receipt retention and shared header actions.
  Disposable QA covered connection/Settings state, calendar-day groups, archive
  selection, read-only archive detail, restore and conversation-scoped Agent
  Changes. Logs: `.build/chat-refinement/chat-lifecycle-tests.log` and
  `lifecycle-final-qa.log`; exploratory Computer Use supplied UI observations.
- **2026-09-07:** 116 activity/file-feedback checks covered typed reads, no-op
  updates, edits, exact receipts, stop/reconnect and mutation admission. Live
  fixture MCP calls preserved two no-op Notes and rejected a stale update.
  Navigation refinement also reported 116 checks, then 97 presentation checks
  and 12 composer checks; these are overlapping runs. QA covered list/detail,
  continued work after Back, Stop, permission, file popover, exact comparison,
  long replies and Light/Dark at 1000/1100pt. Logs:
  `.build/chat-refinement/composer-final-tests.log`, `composer-qa.log`,
  `composer-localization.log`, and `qa-source-proof.json`.
- **Initial client integration, 2026-09-07:** 103 native-conversation and 35
  adjacent checks passed, plus the final menu-route check. Unsaved-selection
  handoff preserved Unicode, BOM, CRLF, editor generation and Undo. Installed
  Codex 0.153.4 passed isolated handshake, account/model queries and thread
  creation without inference. A deterministic runtime exercised streaming,
  steering, cancellation and reconnect. Disposable 500-Note QA exercised real
  App MCP create/update, Ask approval, comparison and byte-identical Undo;
  selection attachment, right Inspector Outline, persistence, bilingual text,
  long replies and 1000–1380pt windows were inspected.
- **Whole-app attempt, 2026-09-07:** static/resource checks, 348 Core tests,
  62 Contracts tests, 126 Application tests and architecture measurement passed.
  Search timing initially exceeded two thresholds; all three performance checks
  passed an isolated repeat at unchanged thresholds. The 637-test App run
  reported 21 issues. Focused import, file-selection and translation repairs
  passed; document scroll, editor projection/bridge and WebKit localization
  failures remained. This is not a passing full gate.
- Release App/CLI compilation and public-symbol validation passed separately;
  Release CLI seven-tool discovery, absent-App refusal and malformed token
  rejection passed. UI-test callers compiled with Xcode 27 beta; compilation
  is not an executed UI journey. Integration logs: `.build/codex-integration/`
  and `.build/verification/`.

Chat QA used deterministic runtimes and nonprivate disposable Triptychs, not
signed-in model inference. Real provider execution, human VoiceOver/IME and
complete adaptation remain unaccepted. Retention of a QA app for researcher
feedback was a dated session arrangement, not a claim about a currently running
process.

### Editor and source interaction

**2026-09-07 syntax continuity —** 228 editor tests, TypeScript/resource reproduction,
Debug App/test compilation, and 16 Swift/WebKit checks passed on Xcode 27 beta
(27A5218g). Fixture QA covered Callout placement, Chinese paste/Undo, disclosure,
Light/Dark, doubled text and mode switching; Undo restored identical bytes. Evidence:
`.build/editor-presentation-*.log`.

**2026-09-06 opening/title readiness —** Four regression checks passed. A 25-second QA
recording (1,427 decoded frames) had no YAML OCR hits during switching;
upward-scroll/reopen checks passed. A four-opening probe reported roughly 60ms
additional warm latency. This is neither a timing gate nor proof against every
compositor race. Evidence: Original opening-readiness QA and task observations; no
independent log path was recorded in the prior status..

**2026-09-05 syntax activation —** 219 Web/resource tests and 100 distinct focused
native checks passed, including construct boundaries, composition deferral, Callouts,
footnotes and 200% text. Keyboard QA preserved exact Markdown through autosave.
Evidence: `.build/syntax-presentation/`.

**2026-09-05 heading input —** 218 Web/resource tests and three WebKit checks passed;
keyboard QA (22.433s) covered entering/leaving headings, marker deletion and Undo.
Evidence: `.build/heading-editing/`.

**2026-09-05 completion —** 99 focused checks and a 32.531s QA journey passed for
retained native host, autosave, pointer/keyboard acceptance, Undo/Redo, Escape and
bounded geometry. Evidence: `.build/completion-refinement/`; earlier
`.build/floating-choices/`.

**2026-09-05 floating surfaces —** 142 focused native checks, 217 Web/resource tests and
five UI journeys passed for Find, completion, notification placement, Search and
footnotes. An old DOM assertion stopped that full-gate attempt; its correction was not a
rerun of the gate. Evidence: `.build/liquid-glass/`.

**2026-09-05 formatting routes —** 42 Swift/WebKit checks and 214 Web tests in 38 files
passed for unobscured selection, native formatting dispatch and mode transitions.
Evidence: `.build/editor-formatting-removal/`.


The 2026-09-07 geometry probes settled animations before measuring; they do not
establish motion timing. Its minimum-width, system adaptations, conflict/
recovery, installed-IME and human perceptual acceptance remain open. Older
passes cover only their named source and interaction, not later editor changes.

### Native shell, Search, Metadata and Settings

**2026-09-06 toolbar/Search —** 87 tests in eight suites; UI journeys for no-document
availability (21.322s) and quick/advanced query handoff (41.820s). Evidence:
`.build/native-toolbar-search-owners.log`, `native-toolbar-search-ui.log`,
`native-toolbar-search-final-build.log`.

**2026-09-06 Library/Search —** 77 tests in six suites; 33.690s Search journey for
composition, query retention, opening and close. Evidence:
`.build/sidebar-owning-tests.log`, `.build/sidebar-ui-test.log`.

**2026-09-06 continuous Metadata —** 11 tests in four suites; disposable 500-Note QA at
980pt covered Light/Dark, native Tab order, Escape, field departure, invalid drafts,
conflict/reload and persistence. Earlier 29 link-navigation checks overlap. Evidence:
`.build/continuous-metadata-tests.log`, `continuous-metadata-build.log`,
`continuous-metadata-localization.log`, `inspector-final-tests.log`,
`inspector-reader-tests.log`.

**2026-09-06 notification tracking —** Six focused checks; native clipping probe and QA
scrolling. Evidence: Original task Computer Use and native probe; no separate log path
recorded..

**2026-09-06 notification delivery —** 48 checks for authorization, denial, coalescing,
cancellation, exact routing and nonreplayed cold handoff. Fixture QA included
Light/Dark, 500pt width, local errors and focus. Real OS permission/click delivery and
human adaptation were not established. Evidence: Original notification task checks and
Computer Use observations..

**2026-09-06 Appearance/Settings —** Configuration reload, invalid/stale edits,
YAML/Undo and managed About checks passed. A reported complete repository run included
609 App tests, public symbols and Release compilation; later changes and failures
supersede it as a current gate claim. Evidence: Original Appearance task verification;
no independent log path recorded..

**2026-09-06 Settings follow-up —** 44 owning tests and 24 overlapping spacing checks;
seven-pane QA, and researcher acceptance of top-left pane animation. No full-gate
repeat. Evidence: Original Settings task and Computer Use observations..

**2026-09-05 Library file actions —** 115 tests and 27.819s organization journey covered
filters, native row size, contextual Move and cancellation with identical source.
Evidence: `.build/sidebar-refinement-logs/`.

**2026-09-05 native command adapters —** 100 checks and four QA journeys covered Find,
menus, information, default/disabled/destructive and cancellation. These establish that
dated adapter behavior, not conformance to the later native-design decision. Evidence:
`.build/button-consolidation/`.


Metadata's earlier QA included interfaces later removed; it does not establish
the current complete Inspector. Earlier Sidebar Outline and vertical-workspace
navigator journeys are superseded as shell-layout proof by the Chat/right-Outline
and segmented-workspace changes. Their historical task logs remain in Git's
prior document revisions. Human accessibility remains separate from all runs.

### Research-record removal and preceding integration boundaries

**2026-09-07:** 106 focused checks passed for Search, window/router, localization,
MCP and scene ownership. Later interface-repair runs reported 105 checks plus
four follow-ups (108 distinct overall), and residue removal reported 83 initial
and 136 final checks with overlap. Disposable QA checked ordinary Works Note
search, native Metadata input and Links, annotation navigation, frontmatter Undo
and opening readiness. Logs: `.build/records-removal/`, `.build/interface-repair/`
and `.build/residue-cleanup/`.

That complete verifier stopped after 347/348 Core tests: a generated-state
corruption fixture reported `couldNotExecuteSQL` concurrently and passed alone;
the cause was unconfirmed. The later Chat whole-app attempt above is the current
broader evidence boundary, not a retroactive pass for this source.

**2026-09-05:** a prior integration passed Web/resource and static guards,
351 Core plus three performance checks, 65 Contracts and 128 Application tests.
It stopped on four obsolete App assertions; the corrected App run passed
591 tests in 44 suites, with public-symbol and Release checks separately.
It was not one clean gate invocation. Logs: `.build/interface-repair-logs/`.

None of these records establishes packaged distribution, G7, physical Full
Keyboard Access, installed Simplified Chinese IME, VoiceOver or full visual
adaptation acceptance. Profile-specific open work remains in its owning chapter.
