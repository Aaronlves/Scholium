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

**2026-10-13 — `v0.4.0-beta` published:** Exact clean tag
`7a6fee4aaeba85dea1b94e570bc9902481e97d74` produced arm64 ad-hoc DMG
(version `0.4.0`/build `18`; macOS `26.0`, SDK `27.0`), SHA-256
`1c3d7a1a8725adb18d299935ef51cc01d0a08dafe6b0745e5deaf7813d5a1245`; the
[public release](https://github.com/Aaronlves/Scholium/releases/tag/v0.4.0-beta)
includes the DMG and checksum. Local `verify.sh` passed WebEditor (1,228), Core
(690), Contracts (173), Application (345), App Swift Testing (1,876), and
Release/helper checks; display-gated checks and the fresh-query microbenchmark
were skipped. Full-profile [GitHub Verify](https://github.com/Aaronlves/Scholium/actions/runs/38292093172)
failed with three issues across two App tests: Chat toolbar retained-resize
timed out with its window not key; External Markdown had `canSave == false`,
leaving `save()` unevaluated. CI was not rerun at researcher direction.
Package integrity passed; XCTest/XCUITest, mounted/copied first-launch smoke and
packaged performance campaign were omitted. G6/G7/G9 remain incomplete.

## Current feature coverage

**2026-10-16 — Settings:** 500-Note Debug service proxy, three samples/arm:
metadata median 629.55→4.44 ms, vault opens 3→0; borrowed +0.65 ms.
106 metadata and 99 Settings regressions pass. Initial Workspace snapshot/fast
portable lookups 2→1 each; hidden History reads 1→0, capability RPCs 3→0;
admitted work finishes. Twenty warm observations/57 captures pass;
layout stays comparable. `.build/performance-evidence/` comparisons:
`settings-metadata-comparison.json`, `settings-retained-read-comparison.json`,
`settings-native-layout-comparison.json`. Prior Storage's 244 regressions/native
recovery remain `.build/index-lifecycle-management/results.md`. Native input/paint,
Chinese body, VoiceOver/researcher acceptance remain open.

**2026-10-10 — Retrieval:** Long-focus title/alias and identity-lifecycle
regressions pass with exact source/highlight checks (`.build/long-focus-proof/`).
Usefulness and native latency remain open.

**2026-10-11 — Native repairs:** Scoped source-ahead move, native Trash/receipt/restoration
and live empty-folder tests pass. Uniform icons and inset glass tabs retain native
geometry; Inspector no longer has a late width jump. Gate/UI results, source hashes,
measurement and cleanup limits: `.build/native-repairs-20261011/result.json`.

**2026-10-08 UTC — Coordinated checkpoint:**
`.build/coordinated-checkpoint-20261008T131206Z/result.json` binds citation/recovery/export
and companion-label source, checks and review. Native Chat/citation, AX/VoiceOver,
external Review-to-Edit, input and adaptation acceptance remain open. Earlier
file/window/Zotero evidence: `.build/feature-audit/`, `.build/file-move-qa/`.

**2026-10-04 — Native baseline:** Thirty-three journeys passed; two organization/passage
journeys are qualified by Trash privacy denial. Xcode 27.0 (27A5218g), Swift 6.4,
SDK 27.0, macOS 27.2; standard 500-Note Triptychs, three registrations. Historical
maps/logs: `.build/feature-review/RESULTS.md`, `.build/feature-review-extension/RESULTS.md`.

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
| Settings | Seven panes, appearance/CSS, writing, shortcuts | Toolbar/search, scoped drafts | Invalid reload, repair, cancellation | Settings suites; native navigation/recovery |
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

**2026-10-16 — Full gate (`992740ad`):** Default `verify.sh` passes all
14 phases, including measurement/display, WebKit and clean Release compilation.
`.build/performance-evidence/current-settings-phase-summary.json` binds exact-source
proof, verified local dependencies and retained failures; earlier performance
comparisons remain in `current-performance-phase-summary.json`. Declared skips
remain; packaged, real-service and human acceptance are unproved.

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

**2026-10-15 Chat entry:** Native remount geometry drift 303/560→0 points;
`.build/chat-entry-layout-audit/`. Offscreen probes establish geometry, not paint
or acceptance.

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

- **Task-authorized 433-Note private-copy evaluation, all roles:** byte-verified
  copy with tests on a second disposable copy. Configure 24.963 s; 20 backend
  queries median/sample p95 1.840/1.975 s versus 2.546/2.731 s immediately before
  native optimization. All 16 private cases preserve ordered results; source
  bytes unchanged. This recorded exception is not standing private-vault authority.
- **2026-10-16 local Release:** 5,000 Notes/57,299,729 bytes; cold/rebuild
  166.509/165.970→154.363/153.652 s (one lifecycle/variant). Three same-seed
  reopens/variant: source-ready p50 10.592→2.378 s; full 18.330→17.894 s.
  Final-factor regression: three opens, source-ready/full p50 2.178/17.303 s;
  source load 61.845 ms, exact unsaved-buffer This Note Search 0.938 ms.
  `.opening` precedes validated index admission; `.complete` follows.
  Exact source, Search/Graph, current generations and closed journals pass.
  The summary binds runs/formatting; native readiness remains unmeasured.
- **2026-10-16 Release Search presentation:** Complete-hit mixed
  2699.545→806.635 ms (1.57 MB), dense CJK 77.506→52.034 ms (1.08 MB), 20 samples/three warmups.
  Current-note API (3,822 bytes), 200 occurrences/20 returned, offsets 0/20:
  290.192/290.199→6.988/7.338 ms (three samples/one warmup).
  Byte-equal responses and manual UTF-16 oracles pass. Source hashes:
  `.build/performance-evidence/search-presentation-comparison.json`.
- **2026-10-16 Release Review preparation:** semantic/fresh medians
  427.240/637.659→274.239/475.930 ms (520,865 bytes; three samples).
  `.build/performance-evidence/further-comparison.json` binds optimized/testable
  builds and stale-label corrections. Native paint, packaged gates and retained
  memory remain unverified; OS caches were not purged.
- **2026-10-16 Related allocation:** One fresh query per arm (5,000 Notes plus seed)
  shows sampled whole-process live-malloc peak increase 390,715,904→319,899,568
  bytes (18.12% lower); three digests/six exact passages agree, without omissions.
  `.build/performance-evidence/related-query-allocator-comparison.json`.
  This establishes neither RSS, retained memory, leaks, exact peak nor native
  latency; no practical speed gain is claimed.
- **2026-10-16 editor-state proxy:** Production TypeScript under Node/V8;
  18 edit/position series, three warmups/20 samples. Series medians for state
  transaction plus citation catalog: 0.247–0.518 ms (51,843-byte prose),
  1.307–11.201 ms (1,096,763-byte CJK). Complete-tree, exact-source and
  Undo/Redo oracles pass. The summary binds raw results. This excludes WebKit
  plugins, native input, layout, paint and save; no paired improvement claim.
  Historical attached-editor preparation retains its prior scope.

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
`.build/index-lifecycle-management/`, `.build/search-opening-diagnostics/`,
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
