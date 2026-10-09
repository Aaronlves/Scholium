# Implementation Status: Verification Evidence

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Dated proof and its limits.

## Release artifacts and gate provenance

**2026-09-27 — `v0.3.1-beta` packaged baseline:** Exact source commit
`7d77c68ce01231b86619b75487172d13f2053e94` produced
`Scholium-v0.3.1-beta-macos-arm64.dmg` (version `0.3.1`, build `12`, macOS
`26.0`, SDK `27.0`, arm64, ad-hoc). Its SHA-256 is
`a6296c8309b99bd7aea1b1b73f6eb9b8fa8a4207d1ce498225d4dc7fa3fb67ca`. The
[public release record](https://github.com/Aaronlves/Scholium/releases/tag/v0.3.1-beta)
reports the complete performance gate, 13/13 affected UI journeys, and mounted/
copied clean-account save/readback smoke; VoiceOver, input, adaptation, icon,
and Finder-restoration human acceptance remain open.

**2026-09-28 — `v0.3.2-beta` packaged candidate:** Exact clean tag at
`e225a72e5320f195adf154815f9c468e43e6d93a` produced
`Scholium-v0.3.2-beta-macos-arm64.dmg` (version `0.3.2`, build `13`, minimum
macOS `26.0`, SDK `27.0`, arm64, ad-hoc). `verify.sh` passed WebEditor (491),
Core (581), Core performance (3), Contracts (105), Application (236),
architecture measurement (1), and App (1,197); Release build and helper
isolation passed. Package checks passed for provenance, resources, licenses,
icon, private paths, entitlements, signatures, architecture, read-only DMG
mount/copy and SHA-256 `590023c506635c6dc2f539281a744d40d4fded11857307b2bb12ba3be28b48d8`.
Per researcher direction, XCUITest journeys and the mounted/copied clean-account
smoke were not run; affected UI journeys, human icon inspection, and G6/G9
evidence remain incomplete.
Logs: `.build/verification/` and `.build/verification-release/`; local candidate:
`~/Applications/Scholium Builds/v0.3.2-beta/`.

## Current feature coverage

**2026-10-10 — Retrieval:** Long-focus title/alias and identity-lifecycle
regressions pass with exact source/highlight checks (`.build/long-focus-proof/`).
Usefulness and native latency remain open.

**2026-10-08 UTC — Coordinated development checkpoint:**
`.build/coordinated-checkpoint-20261008T131206Z/result.json` binds source, checks
and review, including prior daily/headless and citation/offscreen evidence.
Compact citations, paired recovery and static exports have scoped proof.
Conflict comparison explicitly names companion replacement for accessibility;
native AX/VoiceOver remains unverified. Foreground suites, native Chat/citation
acceptance, external Review-to-Edit blankness, physical input and adaptations
remain open; the full product gate is incomplete. Earlier native file/window
and embedded Zotero proof remains under `.build/feature-audit/` and
`.build/file-move-qa/`; fixture hashes and recovery are preserved.

**2026-10-04 — Retained native baseline:** Thirty-three journeys across baseline
and extension passed; two organization/passage journeys remain qualified by
system-Trash privacy denial. Xcode 27.0 (27A5218g), Swift 6.4, SDK 27.0, macOS
27.2; disposable standard 500-Note Triptychs with three separate registrations.
Scenario/assertion maps and logs: `.build/feature-review/RESULTS.md` and
`.build/feature-review-extension/RESULTS.md`. These are dated, not fresh execution.

| Feature/workflow | Normal use | Keyboard/accessibility | Empty, error, interrupted or repeated flow | Verification/findings |
| --- | --- | --- | --- | --- |
| Triptych setup/access | Create/connect three roles | Native File/pickers | Wrong folder, cancellation, restore/relaunch | Bootstrap lifecycle; native setup/access |
| Library navigation | Roles, tree, disclosure, filters/sort | Native rows/arrows, multi-selection | Filtered empty, unavailable, retained Document | Sidebar/Discovery; native navigation/organization |
| New Note/Folder and title | Immediate creation, inline rename | File/Add, body focus, title field | Collision, repeated creation, stale selection | Source-ahead regressions; native creation/Edit/save; `.build/managed-note-opening-20261009/` |
| Opening, tabs and history | Repeat/open/new tab, Back/Forward | Menus, tab/window routes | Failed hydration, retained session, close failure | Fixed cross-role origin preservation; opening regressions |
| Review/Edit/Source | Exact source, YAML, semantic Markdown | Mode/Format/Insert, task/footnote actions | Malformed/protected syntax, Undo, composition | Window-owned mode; native roles/tabs/caret/viewport/Undo; editor/Callouts/clipboard |
| Find and completion | Find/Replace, slash/Wikilink/Analysis candidates | Return/Tab/Escape, named fields | No match, cancellation, Undo, marked text | Editor Find/completion; native journeys |
| Save/conflict/recovery | Autosave/manual save, external refresh | Shared Save, comparison/repair controls | External conflict, interrupted editor, late input | Fixed stable-Note save identity, late-input/close suspension and scroll ownership; fixture/WebKit regressions |
| Quick/Advanced Search | Lexical/property/Boolean/direct-link queries | Native field/results and keyboard opening | Invalid/empty/limited/stale, cancellation | Search suites; native result opening |
| Search helpers | Saved Searches, term groups, paragraph locations | Explicit insertion/explanation/destination names | Invalid store, changed drafts, bounded pagination | Named fields/Escape/geometry fixed; native locators and saved/group management |
| Links | Incoming/Outgoing/External, annotations | Named selector/filter/disclosure/source actions | Missing/ambiguous/repeated links, retained context | Connections/parser suites; native direction checks; formatted annotations readable in exploratory fixture |
| Related Material/Writing References | Current line/selection, source, links, Chat staging | Research shortcut, named cards/actions | Loading/empty/failure, departure/cancellation, stale source | Related Material/paragraph-link suites; native lifecycle; usefulness remains human |
| Note/Folder organization | Duplicate/move, drag, batch operations | Menus, destination sheets, redundant drag routes | Collision, partial/retry/cancel, uncertain Trash | Native Duplicate/Move/collision retry/Trash cancel; committed Trash privacy-blocked |
| Passage reorganization | Copy/extract/move/merge, exact preview | Research/menu destinations and property choices | Partial/protected selection, stale revisions, rollback | Native Copy/Extract/Move commits and Merge preview/cancel; Trash verification blocked |
| Attachments/images | Copy/reference/import/index/paste, Quick Look, inline Edit/Review | File/Insert and named preview routes | Missing original, unsafe path, insertion rollback | Native image admission/geometry/source; copy/reference/import/Undo/Quick Look; cross-app untested |
| External Markdown/import | Open/reopen, captured unsaved import | Toolbar/File/Finder routes | Conflict/reload, collision, uncertain import | External lifecycle/import tests and native journey |
| Export | HTML/PDF/DOCX snapshot/presets | Format/style/Save panel | Cancel, destination failure, long tails/footnotes | Native unsaved HTML/DOCX readback/Save cancel; prior disposable PDF export |
| Changes/Agent receipts | Pending/History, review, exact Undo | Difference/review/receipt controls | Newer revision, unknown baseline, ineligible Undo | Change/Agent suites; native update/restore/History delete/cancel |
| Offline Chat | Conversation/draft/Find/material/queue/archive | Page/composer/selection routes | Retained drafts, sharing, failed deletion save | Fixed cleanup/native Undo lookup; native archive/restore/delete/shared copies/relaunch |
| Runtime Chat | Models/Skills/tools/context/quota, questions/approvals/branches/Agents | Named capability/process/source controls | Unsupported/disconnect/Stop/uncertain delivery | Deterministic runtime fixtures; real provider/account breadth untested |
| Settings | Six panes, appearance/CSS, writing, shortcuts | Toolbar/search, scoped drafts | Invalid reload, repair, cancellation | Settings suites; native navigation/recovery |
| Windows/layout | Independent/detached/external, Focus/full screen | Native menus/tabs/transfer | Close guards, transfer failure, focus restoration | Lifecycle suites; native inherited/destination mode, transfer/caret/Undo/focus |
| Notifications/Zotero | Local queue/exact link display | Named bell/actions/references | Empty/stale, missing target, unavailable integration | Deterministic routes; actual banners/clicks and Zotero untested |

The reports retain corrected harness assumptions and failures alongside passes;
no performance improvement is claimed.

Committed Trash/Merge acceptance and cleanup remain privacy-blocked. One synthetic
Merge file in system Trash still needs manual cleanup; exact path and denied
attempts remain in the extension report.
Review refresh re-resolves local images; unchanged Markdown/lifecycle does not
continuously watch image files. Captures are inspected; real providers/Zotero,
VoiceOver, physical IME and complete adaptations remain unverified.

**2026-10-05 — Inline images and recovery notices:** Native fixtures verify
proportional Edit/Review images, escaped paths, complete caption source,
load/resize/mode/document switches, caret/selection/Undo and denied-resource fallbacks.
Native QA checks menus/arrows and light/dark adaptations; compact persistent
recovery notices retain actions at 300/520 points. Original private-Note/installed-
binary reproduction and human VoiceOver remain unverified. Evidence:
`.build/image-inline-evidence/RESULTS.md`.

Complete repository gate stages pass: WebEditor 557, Core 586, performance 3,
Contracts 107, Application 246 plus bridge 6/architecture 1, and App 1,379
reported tests (31 conditional render/runtime/timing skips), localization,
public API boundaries, Release and helper isolation. The final gate process stopped
mid-App without a failure summary; complete App and remaining stages resumed against
unchanged implementation hashes. Logs: `.build/image-inline-evidence/final-gate.log`,
`final-app-resumed.log` and `final-gate-continuation.log`, plus `.build/verification/` and
`.build/verification-release/`. QA runtime state is removed and all 506 standard
fixture manifest files retain their hashes. No publishing or real-service proof.

**2026-10-05 — Saving/recovery and presentation:** Prior native fixture QA preserves
accepted bytes through switching, caret return, closure and graceful relaunch.
SIGKILL fixtures distinguish staged edits, committed source and unstaged input;
incomplete ledgers preserve other recoveries. Reviewed gate, Chat visibility and
Review/Edit checks: `.build/saving-recovery-ux-evidence/summary.json`; recovery:
`.build/saving-recovery-continuation-evidence/checkpoint.json`. Native QA confirms
off/on/search/relaunch and retained drafts. Physical IME/VoiceOver and private/system-service
paths remain unproved.

Retained prior native baselines remain bounded: 2026-09-16 Bootstrap/editor
conflict and recovery (`.build/bootstrap-verification/RESULTS.md`,
`.build/editor-boundary-evidence/`); 2026-09-28 Changes/history/source preservation
(`.build/changes-complete-gate-green-candidate.log`); 2026-09-30 toolbar/transfer
(`.build/tab-native-optimized-acceptance.log`); 2026-10-01 Settings five journeys
(`.build/settings-native-optimization/RESULTS.md`); and 2026-10-02 offline Chat
(`.build/chat-optimization/`). They are not relabelled as current execution.

Distinct safety baselines also remain effective: 2026-09-13–15 late-writer,
reorganization and Library batch checks protect exact external bytes,
revision-checked restoration, partial retry and source/resource relocation
(`.build/note-safety-fix/`, `.build/source-cutover/`,
`.build/knowledge-reuse-fixes-tests.log`,
`.build/library-file-operation-final-tests.log`,
`.build/file-operation-final-layout-tests.log`, `.build/file-operation-review/`).
The 2026-09-17 Writing References identity/locator checks cover exact revisions,
duplicate titles, source mismatch and cancellation
(`.build/reference-interface-fix-acceptance.md`,
`.build/reference-interface-fix-tests.log`,
`.build/reference-interface-fix-navigation-integration-recheck.log`,
`.build/retrieval-ui-acceptance.md`, `.build/retrieval-ui-state-tests.log`).
Live sync/File Provider, post-Trash cleanup, physical input and human Recovery
remain outside those baselines.

**2026-09-08 — Retained signed-in Chat loop:** Official-runtime QA completed
multi-turn read, native approval, exact Note update, comparison, eligible Undo,
restart restoration and Stop, returning source to its starting bytes. This is
only that route, not fresh account/provider or Zotero breadth.
Evidence: `.build/agent-chat-evolution/real-loop-retest-*.json`.

## Retrieval quality and useful measurement comparisons

**2026-09-23 — Retrieval:** Related-Content 14/ranking 12: source-line focus,
silent bounded Note preparation; focused eligibility/ranking preserved.
Unit/native checks cover exact capture, cold/prepared/rebuilt equivalence, invalidation,
corruption, cancellation and narrow-source reads.
Synthetic graph ablations preserve stronger unconnected material and improve
tied/selective ranking, without researcher acceptance.
Scorer results remain bit-identical over 8,000 paragraphs with 3/32 terms.
In three paired 500-Note Debug restarts, preparation
reduces foreground median 1.361→0.873 s, with 0.807–0.821 s background work;
paired and 21 prior source/locator results remain identical.
Evidence: `.build/two-layer-retrieval/`, `.build/retrieval-architecture/`,
`.build/retrieval-optimization/`, `.build/recommendation-graph-evaluation/`,
`.build/writing-references-performance/`.
Measurements below exclude editor capture/debounce, link-action preparation and
native publication; they are not G7 or click-to-paint acceptance.

- **2026-09-17 2,000-Note Release harness:** generated multilingual Notes, 16
  paragraphs each, plus Works seed. Configure 37.274 s; first query 2.883 s;
  repeats 2.003–2.012 s versus 3.222–3.256 s immediately before normalization/
  scan protection; varied focus 1.818–2.377 s; selected draft paragraph 2.327 s;
  reopen 5.716 s plus first query 2.786 s. Retention estimate remains 64 MiB;
  all candidates are checked/scored.
- **2026-09-23 500-Note Debug harness:** generated three-role corpus, 16 paragraphs
  per Note; Xcode 27/Swift 6.4. Identical-input warm medians after reopen:
  0.714 → 0.649 s; selected long focus: 1.604 → 1.129 s. Two repeats per
  workload, not p95; all 21 ordered result digests agree. Prepared-scorer medians
  across five samples: 3 terms 101 → 40 ms; 32 terms 593 → 153 ms.
- **Task-authorized 433-Note private-copy evaluation, all roles:** byte-verified
  copy with tests on a second disposable copy. Configure 24.963 s; 20 backend
  queries median/sample p95 1.840/1.975 s versus 2.546/2.731 s immediately before
  native optimization. All 16 private cases preserve ordered results; source
  bytes unchanged. This recorded exception is not standing private-vault authority.
- **Expanded standard 500-Note Debug refresh, schema 19:** 6,973,820 bytes.
  Cold configure 35.91 → 13.05 s; reopened usable state 10.94–11.03 → 2.99–3.10 s;
  completion after presentation signal 17.33–17.45 → 4.87–4.93 s; unchanged refresh
  2.26–2.30 → 0.750–0.756 s. All 500 projections restore without recomputation;
  authorization/parsing remain fresh.
- **2026-09-15 Search benchmark, 2,056 Notes:** schema 18 / ranking policy 4.
  Warm query p95 97 ms, first five pages p95 466 ms, incremental publication
  p95 27 ms against unchanged 100/500/250 ms budgets. A dated measured-build
  result, not current packaged performance.
- **2026-09-16 editor reuse:** synthetic 60-paragraph Debug Edit, two warmups and
  five samples/path. Median attached-editor preparation 197.438 → 50.358 ms,
  including capture, pool clearing, bridge readiness and DOM layout. Throttled
  WebKit frame delivery excludes paint/Release claims.
- **2026-09-16 Settings:** Debug Time Profiler + Hangs, six warm Appearance
  selections. Median hosting-layout CPU sample weight 72 → 40 ms; action-window
  main-thread weight 225.5 → 200.5 ms; no detected >250 ms hang versus baseline
  first-Appearance 267.9 ms. Workspace totals overlap; not click-to-paint.

Synthetic quality cases split 18 development/18 heldout: distinct-material nDCG@6
0.601/0.641 → 0.635/0.717; material recall 0.625 → 0.688/0.750. Agent-authored cases are
not blind validation or researcher acceptance; raw Note recall falls when duplicate
material is represented once. Earlier private aggregate known-useful recall@6 was 0.375;
one earlier ranking change replaces a judged sixth result with unjudged material.
Incomplete pools cannot establish improved/worsened philosophical usefulness.
Agent review of 12 passages in two changed cases finds no coordinate defect and
additional relevant material, not overall precision or researcher acceptance.

The ignored Python/ONNX multilingual prototype yields known-useful recall 0.479,
or 0.500 with fixed lexical/semantic RRF, but 72/96 hybrid results are unjudged and
Chinese-query recall is 0.200. Different paragraph preparation, absent App wiring
and unverified distribution mean this is neither a shipping backend nor full
precision evidence. Private content/paths, judgments, vectors and model assets
remain outside tracked fixtures.

Evidence: `.build/recommendation-evaluation/`,
`.build/recommendation-private-evaluation/`,
`.build/recommendation-native-comparison.json`,
`.build/recommendation-private-native-optimized.log`,
`.build/recommendation-scan-protection-2000.log`,
`.build/recommendation-final-owning-tests.log`,
`.build/recommendation-native-release-build.log`,
`.build/semantic-multilingual-prototype/`,
`.build/writing-references-release-harness/.build/writing-references-performance/`,
`.build/refresh-optimization/`, `.build/search-opening-diagnostics/`,
`.build/search-performance-final-correctness.log`,
`.build/note-switch/RESULTS.md`, `.build/settings-performance-fix/`.

## Evidence boundary

Compilation, deterministic tests, offscreen renders, exploratory Debug QA,
measurements, packaged smoke and human acceptance establish different claims.
Test counts are not additive. No development entry closes VoiceOver, physical Full
Keyboard Access, installed Simplified Chinese IME, complete visual adaptation,
G7/G9 or packaged external-host acceptance unless explicitly stated.
[Open Work](03-open-work.md) owns remaining limitations; the
[status entry](../IMPLEMENTATION_STATUS.md) summarizes reachability. Superseded
task narratives belong to Git; local `.build` pointers are not release artifacts.
