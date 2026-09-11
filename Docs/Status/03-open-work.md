# Implementation Status: Open Work

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Work and acceptance still open.

## Native design conformance

The documentation decision permits additional background and Accent only in
the main workspace; all auxiliary surfaces use system appearance. This is a
target decision, not an implementation or acceptance pass. Audit reachable
command-tint adapters, custom row/pointer feedback, preview WebKit CSS and
inherited auxiliary-window palettes against Design. The document renderer's
source fidelity and researcher-owned content formatting remain separate owners.
This documentation cleanup changes no app code and closes no UI acceptance.

## Agent knowledge-base and Zotero acceptance

Exact range updates, paginated Library browsing and Agent Change query/compare/
Undo, move-impact preview and identity-preserving move/exact inverse have
implementation slices, together with bounded related attachment text/page/image
reads, session/window-bound Note display and persistent native Chat Zotero
read-only enablement/status, unified Zotero locators and exact annotation/original
reads, with scoped runtime material reports in Sources. Deterministic integration
coverage is recorded in Verification; native acceptance remains. Specification
§§8 and 15 own the approved boundaries; this list is not a completed capability.
Real provider, Zotero page/annotation opening and researcher accessibility remain
unaccepted until separately evidenced. No expanded Zotero write scope is implied.

## In-app Chat acceptance

The expanded target is owned by Specification §8.7 in `12-agent-chat.md`.
Current work prioritizes general Agent interaction before specialized research
features. Selection shortcuts now run Explain, Polish and custom prompts with checked
source context; Ask Agent preserves the ordinary draft-only handoff. Complete representative scholarly
validation across ambiguous concepts, implicit premises and unavailable originals;
passing interface checks alone does not establish philosophical benefit.
Cross-block reply selection, quiet tool details, toolbar Chat Note-copy
drops and tab-preserving source opening now have implementation slices. Keyboard
cross-paragraph handoff and Library menu/native accessibility Add to Chat pass
live. Complete physical Library-to-Chat dragging and human assistive-technology
and adaptation acceptance. Per-hunk MCP change adoption
needs a separate revision-checked implementation; ordinary update approval stays
one decision per proposal. Scheduled execution remains separate
runtime-integration work, not implied by these interaction slices. A bounded
next-turn queue is now implemented in the conversation owner: it retains ordered
researcher messages, offers explicit Send Next/Remove actions, and admits the
first item once after a matching completed turn. Provider/live acceptance and
scheduled execution remain open.
The bounded signed-in research loop now passes with the disposable 500-Note
Triptych: multi-turn reading, native approvals, one exact update, comparison,
Undo, restart restoration and Stop. CHAT-LIVE-01/02 are closed for that path;
see Verification for the evidence and limits. Broader provider, concurrent and
philosophical-work acceptance remains open. A real same-turn additional request,
completion while viewing another conversation, independent draft preservation
and automatic recovery from idle runtime-process loss now pass. Complete
prolonged offline and in-flight source-operation crash recovery acceptance. Idle
force-quit recovery of an already-persisted draft and exact Note attachment passes.
Native composer measurement no longer mutates live editor geometry; direct AX
clicks, multiline wrapping and Undo pass in the narrow QA sidebar. Complete assistive-technology and installed-IME
acceptance. Public process, compact reply files, floating controls, Copy and
reply-scoped Sources are implemented, including same-turn Note revision/range
evidence, separate supplied materials and public web-access observations. Real
Note reading, evidence restart retention and a new-thread webpage access pass;
full physical adaptation and motion review remain open. Idle search-setting
renewal is implemented with pending presentation, closed new-turn admission,
runtime-wide idle checks and cancellation. Live QA changes a loaded conversation
from disabled to live search, retains its identity, history, draft and sign-in,
then completes a real web access. Runtime-active/background-command waiting,
malformed observations and launch failure pass fixtures. Complete live delegated
work waiting and provider-specific cached/disabled behavior. Live background-command
waiting now passes: the tool remains running after the reply; settings renewal
waits for command exit, then preserves the draft and login. Associated Skill roots
are initialized before connection readiness; renewal, rejection/recovery and
cancellation pass focused fixtures. Complete combined real-provider Skill-root
restoration acceptance.
Improve discovery guidance for the observed recoverable resources/list probe;
it is not evidence that source reads or the connection failed.
Complete live tool setup/configuration and real-provider authentication acceptance,
declared-dependency availability and search-result provenance. Skill discovery,
inspection, effective enable/disable, local association/removal, explicit message
selection and tool inventory have native implementation slices; verify the folder
picker and shared-setting confirmation in a live window.
The in-app Agent capability surface is now implemented and focused-tested: an
active token-scoped turn can inspect runtime capabilities, manage researcher-owned
Skills and discovery roots, version-check MCP Tool configuration, begin runtime
sign-in and change next-turn Chat settings through the existing runtime owner.
This does not yet replace real-provider/browser acceptance.
Remote/local connection forms and version-checked configuration writes are
implemented, including environment-variable references. Advanced header mappings,
helper programs and structured remote-environment references retain their runtime
configuration owner; the native form preserves those settings without editing them.
The tool authentication client is wired to runtime OAuth requests/completion;
complete browser/provider interaction acceptance when the researcher is available.
Local file snapshots, page-indexed PDF text and image-input preparation are
implemented. Complete actual provider input and native picker, file paste/drop,
Quick Look and image-thumbnail acceptance. Explicit scanned-PDF page-image
preparation and clipboard image paste are implemented. Complete physical Paste,
text Undo and installed-IME acceptance. Bitmap-only image drop is implemented;
complete physical cross-app drag acceptance.
Version-checked source links and attachment opening are implemented; complete
live passage selection and composition acceptance. Also complete live
Note-picker/editor-snapshot acceptance, and delegated and supported scheduled execution. Public delegation requests,
target states and reports are displayed and retained with their original runtime
identities. Reported child opening and exact-turn interruption have an
implementation slice with verified parent chains, paginated inspection and
unconfirmed-interruption handling. Complete real-runtime and native sheet
acceptance. Ask Parent now retains separate child drafts, revalidates ancestry,
and uses the parent conversation's ordinary send/steer path with explicit
parent-receipt states. Closing the inspector preserves admitted input. Search
and branches retain exact target references; edited branches cannot silently
retarget an original child. Complete real parent-mediated delivery and native
composer acceptance. Nested report navigation now retains original parent scope
within one native detail; complete real-provider acceptance. Direct child
messaging, child approval routing and scoped tool admission still need integration;
inspection grants none of those capabilities.
The installed 0.153.4 schema exposes `canAcceptDirectInput`; its published
runtime source rejects direct App Server input for multi-agent v2 spawned
threads. Child messaging must honor that capability and distinguish any request
sent through the parent from confirmed delivery to the child. Do not bypass this
runtime ownership rule by forcing another agent mode.
Background Chat outcome/input notifications are wired through the shared native
notification service; complete actual macOS authorization, banner click and
cold-launch acceptance when the researcher is available. Independent browsing and concurrent execution are implemented with
per-conversation tool admission and a bounded concurrent authenticated bridge.
Search, Find, Rename, exact-turn branching and editing an opening request in a
new branch have native implementation slices.
Branching still needs signed-in official-runtime and live menu/focus acceptance;
unattributed or incomplete runtime history is rejected without creating a local branch.
Complete real-runtime concurrency and live interaction acceptance. Model/reasoning/web-search choices,
context/compaction, public plans and quota have a first implementation slice;
complete their real-runtime and live interface acceptance. Native research
questions now have scoped answers and confirmation; complete their provider,
keyboard/IME and accessibility acceptance. Exact proposed Note update comparisons
are implemented; complete their live sheet and provider-driven acceptance.
Runtime command, terminal, network, file and permission approvals now have native
scope/decision forms; complete real-provider execution and live interaction
acceptance. Persistent command/network policy amendments remain unsupported and
have no granting action. Tool-origin questions show their correlated identity
and offer Stop Turn; complete provider-mediated tool authorization acceptance.
The researcher reauthorized UI automation on 2026-09-08. Use disposable QA
fixtures for current interaction checks; previous offscreen-only evidence does
not become live acceptance. The native-card/tab slice has a live light/dark
Computer Use journey, while provider interaction, complete adaptation and human
acceptance remain open. Glass-backed offscreen bitmap renders can contain
compositing artifacts; inspect the actual native window before judging them.

- The bounded signed-in multi-turn research loop passed. Selection Actions also
  has a real-provider Review-passage discussion; retain broader acceptance above.
  Exact Review return, native Copy and the editable Source fallback now pass in
  the live window. Read-only fallback is defensive: ordinary catalog references
  expose stable identity only for resolved, editable Notes. Verify its behavior
  during identity transitions; do not invent a read-only workflow for acceptance.
  Document/request-bound navigation and repeated activation pass. Revision checks
  at application and CRLF/Unicode offset conversion pass in native WebKit tests;
  Edit/Source return and direct Copy pass live. Timed live filesystem races remain
  outside this evidence.
  Edit/Source native triple-click, floating Ask Agent and exact attachment handoff
  pass live. Source return and native Copy match. Computer Use drag still does
  not establish a range; Edit AX-selected text differs from the visible selection
  and native Copy. Diagnose the WebKit/automation reporting boundary before
  changing selection logic; retain human drag acceptance separately. Source AX and Review pointer selections also have
  matching supplied excerpts.
- MCP form/URL elicitation and paginated imported runtime history are not
  supported in this slice; unsupported server requests are rejected visibly.
  Conversations originate in Scholium and retain their own public history.
- Complete human VoiceOver, installed-IME and visual-adaptation acceptance for
  the Chat composer, approvals, file navigation and Related Material.

## External-host and release acceptance

- Complete the packaged external-host journey required by §21.5. Keep protocol
  variants and failure branches in deterministic checks; do not multiply them
  into a second clean-account matrix. Local checks do not establish production
  App/CLI installation, bridge or packaged-path behavior.
- Complete profile-appropriate distribution provenance, artifact checks and
  the clean-account smoke in §21.5 before claiming a distributable release.
  The source-first Beta uses ad-hoc signing; Developer ID and notarization
  belong only to a future notarized channel.

## Human interface and accessibility acceptance

- Complete human acceptance of the 2026-09-07 editor syntax continuity:
  validate rapid reversal, full-line prefix borrowing,
  minimum width, system adaptations, IME, and conflict/recovery on the changed
  presentation; exploratory QA and editor unit tests do not close these checks.

- The approved Source-font controls,
  Settlement milestone presentation, ordinary Edit body entry, and native-row
  emphasis correction are implemented. Human acceptance remains open; the
  2026-09-05 evidence is recorded in the verification chapter.
- Exercise the original intermittent Sidebar symptom under physical mixed
  pointer/keyboard use and window reactivation. Native row emphasis now rejects
  pointer-mode writeback and no longer resynchronizes during drawing; unit and
  focused XCUITest coverage do not establish every timing-sensitive sequence.
- Re-run the affected Agent Changes exact-comparison/Undo UI journey after its
  isolated-launch failures are resolved. On 2026-09-04 two focused attempts
  failed before Settlement because the registered QA launch did not expose the
  requested disposable Note and instead surfaced stale Restore Access state.
  Direct launch against a disposable repository-local fixture verified the
  native Settlement button, popover, successful state change, and final
  accessibility label under exploratory Computer Use, which is not a
  deterministic journey pass or human motion acceptance.
- Establish the retained Core human baseline: one genuine VoiceOver journey,
  one physical Full Keyboard Access journey, one installed Simplified Chinese
  IME exact-source journey, and one visual-adaptation set at supported window
  sizes.
- Include Agents & Chat command copying, Agent Changes comparison/Undo,
  Library navigation, Inspector About/Links/Related Material navigation and
  Document mode transitions,
  system Trash, conflict, and recovery where they exercise distinct human
  failure modes.
- Retain the current distinction between deterministic build/test evidence and
  human acceptance. Automated accessibility structure checks do not constitute
  VoiceOver, keyboard, IME, or visual acceptance.

## Remaining product work

- Continue performance, File Provider/sync, Finder restoration, and Zotero
  system-integration acceptance where the current specification requires
  artifact or environment evidence.
