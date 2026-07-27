# Researcher-Governed Skills Implementation Roadmap

**Status:** execution guide for the active migration

**Branch:** `codex/researcher-governed-skills`

**Completed product Session:** 17

**Session 17 commit:** `aa76d9d692b7f906340030042c9497a073a0a511`

**Next product Session:** 18

This document lets a fresh Codex task continue the researcher-governed Skills
migration without depending on an earlier conversation. It records sequencing,
scope, verification, and handoff requirements. It is not product authority and
must not be used to claim that a target is already implemented.

## 1. Authority and evidence

Use the repository authority hierarchy in `AGENTS.md`:

1. `Docs/SCHOLIUM_SPEC.md` is the sole target product and interface authority.
2. `Docs/IMPLEMENTATION_ARCHITECTURE.md` owns subordinate structure and state
   ownership.
3. `Docs/IMPLEMENTATION_STATUS.md` owns dated current evidence, migration debt,
   and open acceptance.
4. Live construction, tests, scripts, and Git establish current reachability.

This roadmap owns only implementation order. If it conflicts with the
specification, follow the specification and stop to resolve the roadmap rather
than silently changing a stable product decision. If it conflicts with live
implementation evidence, preserve the safe current behavior and report the
divergence in `IMPLEMENTATION_STATUS.md`.

The desktop proposal may explain the original design discussion, but it is not
a parallel specification.

## 2. Frozen migration boundary

The migration implements D-106's researcher-governed Research Actions and
ordinary editable Method Skills. Agents continuing the work must read the live
D-106 decision and the affected workflow in `SCHOLIUM_SPEC.md`; interface work
must additionally read Sections 18–20 and 22 completely.

The remaining work must preserve these boundaries:

- Scholium mediates bounded requests and writes; it does not embed, monitor, or
  police an external agent runtime.
- A Skill declares required capability but cannot grant authority to itself.
- A frozen parent run is never widened. An approved additional-note request can
  create only a separately prepared and authorized child phase.
- Markdown bytes remain authoritative. Diffs, prompts, transport logs, raw
  coordination keys, bookmarks, absolute paths, and window state do not enter
  portable Research Records.
- Research Records contain only narrow Scholium-observed facts, attributed
  Agent feedback, and deliberate researcher expression. They do not infer
  intention, belief, truth, success, failure, understanding, or acceptance.
- Legacy data stays byte-unchanged and nonauthorizing until its scheduled
  source route is removed. Clean cutover never rewrites researcher Markdown,
  unknown YAML, unrecognized Triptych files, or unsupported legacy data.
- Automated evidence does not establish philosophical quality, Skill
  optimality, accessibility acceptance, researcher visual acceptance, release
  readiness, or truth.

## 3. Mandatory protocol for every remaining Session

Every Session is one fresh Codex task, one bounded implementation step, and one
commit. It must use this order:

1. Open the repository root and confirm the active branch is
   `codex/researcher-governed-skills`.
2. Confirm `HEAD` is the previous Session's reported commit and that its
   ancestry contains Session 17 commit `aa76d9d692b7f906340030042c9497a073a0a511`.
3. Run `git status --short`. Stop rather than mix unrelated or unexplained
   changes into the Session.
4. Read `AGENTS.md`, this roadmap, the affected specification, architecture,
   implementation-status evidence, and only the development skills needed for
   this Session.
5. Before programming, search current official documentation and mature
   existing solutions relevant to the mechanism. For technical claims, prefer
   primary documentation. External sources explain mechanisms; they do not
   define Scholium product meaning.
6. Implement only the named Session. Record adjacent discoveries as deferred
   work instead of implementing the next Session opportunistically.
7. Run focused tests while iterating. Reuse repository-local SwiftPM scratch
   and Xcode DerivedData paths under `.build/`; do not create competing build
   caches.
8. Update `Docs/IMPLEMENTATION_STATUS.md`, separating target, implemented
   evidence, automated evidence, and unverified acceptance.
9. Review the entire Session diff with `git diff --check`, `git diff --stat`,
   and a hunk-by-hunk read. Obtain one independent, read-only reviewer-agent
   review. Fix all P0, P1, and Session-relevant P2 findings, then rerun focused
   tests.
10. Run the complete `./Tools/Scripts/verify.sh` once after the implementation
    and review fixes stabilize. A material interface Session must also run its
    specified journey against one disposable nonprivate TestVault and isolated
    QA state.
11. Commit only after required review and verification pass. If they cannot
    pass, do not commit; end the Session with bounded blocking evidence.
12. Confirm a clean worktree, report the full commit SHA, exact verification,
    and remaining uncertainty, then end the task. Do not begin the next Session,
    push, amend an earlier commit, package, or make a release.

Standing UI-automation authorization is defined in `AGENTS.md`. It does not
need to be requested again, but it remains limited to disposable QA Scholium
instances and nonprivate fixtures.

## 4. Completed Session ledger

The dated claims and open uncertainty remain in `IMPLEMENTATION_STATUS.md`.
This table is only a Git orientation index.

| Session | Outcome | Commit |
| --- | --- | --- |
| 1 | Adopt target workflow decisions | `a5ddcbe` |
| 2 | Define public Action contracts | `845b275` |
| 3 | Split adaptive Method Skills | `46c4355` |
| 4 | Install editable Triptych Working Methods | `6647de1` |
| 5 | Add bounded Action Profiles | `8ffc9a5` |
| 6 | Bind Analyze to explicit source access | `34c3080` |
| 7 | Add static research-interface proofs | `66be145` |
| 8 | Add staged local Skill installation | `0e5ee56` |
| 9 | Build Research Guidance Skill settings | `4477bb7` |
| 10 | Resolve built-in and custom Actions | `0031cbc` |
| 11 | Separate portable records from local execution | `2645aeb` |
| 12 | Unify Comments within Discussion | `28605f6` |
| 13 | Switch and close the simplified production Actions surface | `5bf0813`, `6546a59`, `9d77440`, `db02bcc` |
| 14 | Add bounded standing permissions | `6a317f9` |
| 15 | Define Agent change-request coordination | `94c7385` |
| 16 | Add the local Agent request bridge | `794c239` |
| 17 | Present Agent-requested Note changes | `aa76d9d` |

Do not infer release readiness from this sequence. Some completed Sessions
retain explicitly scheduled migration debt, and support commits in Session 13
closed recovery and Review-mode interaction issues found during acceptance.

## 5. Session 18: permission-bound child continuation

**Commit:** `Add permission-bound research continuations`

### Goal

Turn an allowed Agent Note Change decision into a new independently bounded
child phase. Never mutate or expand the parent snapshot, grant, checkpoint, or
write scope.

### Implementation

- Add versioned lineage/group identity connecting a parent run, request
  decision, and child phase without making lineage an authority source.
- Prepare the child against current live state after approval. Freeze its own
  Action and Profile revisions, Target identities, exact fingerprints, read and
  write envelope, Method revision, source requirements, and completion route.
- Give the child its own checkpoint or exact-note recovery boundary, completion
  key/grant, Fidelity checks, conflict handling, cancellation, and completion
  verification.
- Treat `allowedSubset` as the maximum candidate set, not an instruction to
  write every allowed Note. A child may use only the exact approved subset and
  current Action/Profile ceiling.
- Keep one external-agent conversation possible across phases while exposing
  two independent Scholium authorization phases.
- Support the current continuations:
  - Analyze to Synthesize;
  - Critique to Write;
  - optional Manuscript continuation through the same mechanism.
- If the request is denied, continued without changes, stale, expired, or the
  parent is no longer eligible, create no child grant. Silence grants nothing.
- A parent cancellation, Note revision change, lifecycle change, Skill/Profile
  change, conflict, or failed checkpoint/recovery preparation must fail closed
  without partially authorizing a child.
- Portable and machine-local evidence must keep parent decision, child
  execution, and final Research Record facts semantically distinct.

### Required tests

- subset approval creates only a separately frozen child scope;
- parent snapshot and grant remain byte- and authority-unchanged;
- parent cancellation before child preparation refuses continuation;
- stale decision, changed Note, changed Profile/Skill, and cross-Triptych input
  refuse continuation;
- child conflict and cancellation preserve recovery;
- checkpoint/exact-note recovery restore remains child-bounded;
- Fidelity and partial completion are evaluated for the child itself;
- lineage survives reopen and cannot authorize execution;
- Analyze to Synthesize, Critique to Write, and optional Manuscript fixtures;
- idempotent retry does not create duplicate child runs or grants.

### Explicit deferrals

Do not implement the Research Record browser, Record Trash, disposable diff,
Material Changed Since Use, or Session 22 source deletion here.

## 6. Session 19: independent Research Record window

**Commit:** `Build the scholarly Research Record window`

### Goal

Provide one independent Triptych-scoped scholarly record browser. It is not an
Inspector section, document-owned panel, Discussion panel, or chat transcript.

### Implementation

- Use an independent utility scene/controller with its own window lifecycle.
- Opening from a Note initially applies `This Note`, but the researcher can
  clear the filter and browse the Triptych.
- Use two columns at ordinary width:
  - left: one row per Discussion or run, with derived title, date, pin,
    participants, and public Action;
  - right: full attributed Discussion or run, Agent feedback, researcher
    replies, and collapsed Record Details.
- Search and filter by Note, date, Skill, Action, and participant using a local
  rebuildable derived index.
- Switch to stacked navigation at narrow width.
- Preserve an editorial, work-like reading rhythm: attributed prose, quiet
  rules, no chat bubbles, no middle-dot separators, and no invented verdict.
- Support tombstoned Note participants, deep links, independent window
  restoration, keyboard navigation, Dynamic Type, and accessibility structure.
- Do not persist a row per turn and do not automatically summarize or delete
  records.

### Required tests and QA

- large portable record collections and derived-index rebuild;
- Discussion and nonconversational run presentation;
- Note tombstones and cross-Note records;
- search/filter combinations and deep links;
- ordinary two-column and narrow stacked layouts;
- window reopen/restoration, focus, keyboard, and VoiceOver structure;
- light/dark, Increase Contrast, Reduce Transparency, Reduce Motion, and large
  text against a disposable TestVault.

## 7. Session 20: Record Trash and disposable comparison

**Commit:** `Add record recovery and disposable comparison`

### Implementation

- Add manual Move to Trash, Restore, and confirmed Permanently Delete for
  portable records.
- Removing a shared record removes all of its derived Note projections without
  deleting Markdown, checkpoints, exact-note recovery, or unrelated records.
- Keep deletion researcher-initiated and recoverable until permanent deletion.
- Generate a diff only on explicit request from exact start/end fingerprints
  and available checkpoint/current/recovery bytes.
- Never persist diff hunks. If either exact revision cannot be established,
  show `Comparison Unavailable` rather than approximating.
- Make large comparison cancellable and keep source bytes authoritative.

### Required tests and QA

- Trash/Restore round trip and confirmed permanent deletion;
- shared-record projections across Notes;
- missing checkpoint/recovery and mismatched fingerprint refusal;
- byte fidelity, large-file cancellation, and absence of persisted hunks;
- keyboard, focus, accessibility, and recovery states in the independent
  Research Record window.

## 8. Session 21: Material Changed Since Use

**Commit:** `Add revision-bound synthesis attention`

### Implementation

- Derive the condition only from a completed Synthesize record's Agent-reported
  and Scholium-validated `actually used` Analysis set.
- Never treat selected Material as actually used.
- Compare the recorded exact Material revision with its current revision.
- Present `Material Changed Since Use` through the existing Attention surface
  with `Inspect`, `Resynthesize`, and `Leave Unchanged`.
- Do not state that a Topic is wrong, outdated, disproven, or in need of change.
- Bind dismissal to the Material identity and exact revision pair; a later
  Material revision creates a new condition.
- Route Resynthesize through Session 18's independent child-phase authority.

### Required tests and QA

- selected-but-unused Material creates no Attention item;
- one and multiple changed revisions;
- deleted record and tombstoned Material behavior;
- Leave Unchanged dismissal and reappearance after another revision;
- Inspect route and Resynthesize child phase;
- derived-state rebuild and no mutation of Topic or Research Record facts.

## 9. Session 22: clean-cutover closure

**Commit:** `Close the researcher-governed workflow cutover`

### Implementation

- Remove every still-reachable old Action, Research Activity HUD, Comment-only
  route, old record projection, and superseded construction path.
- Remove scheduled unreachable legacy source, decoders, tests, and resources
  only after proving the replacement is reachable.
- Preserve old data files unchanged and retain `Reveal Legacy Data` without
  parsing, migration, projection, or new authorization.
- Audit public terminology: no public Develop, Revise, Proposal, old Activity
  HUD, or middle-dot separator.
- Reconcile `SCHOLIUM_SPEC.md`, architecture, status, README, live
  construction, tests, packaged resources, and localization.
- Compare the completed branch against the desktop proposal as a final omission
  check only; resolve product meaning in the specification rather than making
  the proposal a second authority.
- Do not describe automation as research correctness, philosophical quality,
  release acceptance, or evidence that a Skill is best.

### Required end-to-end fixtures

1. Source route: Source Reference to Analyze to Fidelity to Synthesize to
   Material Changed Since Use to Resynthesize.
2. Argument route: Discussion to Critique to authorized Write to recovery and
   Fidelity.
3. Researcher Skill: safe installation to edit to custom Action to permission
   invalidation and renewed approval.
4. Agent request: MCP/CLI to native sheet to subset approval to child phase.
5. Clean cutover: old files, bindings, and grants remain byte-unchanged,
   invisible, and nonauthorizing.
6. Privacy: keys, prompts, bookmarks, absolute paths, and diffs never enter
   portable records.
7. Multiwindow, conflict, cancellation, recovery, Record Trash, and permanent
   deletion.

### Final review

- Review the complete branch diff against `main`.
- Run complete `verify.sh` and the isolated complete UI suite.
- Exercise light/dark, Increase Contrast, Reduce Transparency, Reduce Motion,
  keyboard, focus, VoiceOver structure, and CJK IME with disposable data.
- Preserve every remaining human/release acceptance item in
  `IMPLEMENTATION_STATUS.md`; do not call the branch release-ready without the
  separately required evidence.
- End with a clean worktree. Do not push until the researcher explicitly asks.

## 10. Fresh-task handoff template

Use this prompt for the next task, replacing the Session number, base commit,
and exact Session section when appropriate:

```text
Continue the Scholium researcher-governed Skills implementation with Session 18
only. Work in /Users/jacuqeas73/Developer/Scholium on branch
codex/researcher-governed-skills. Read AGENTS.md and
Docs/RESEARCHER_GOVERNED_SKILLS_IMPLEMENTATION_ROADMAP.md completely, then
follow its Session 18 contract and mandatory Session protocol. Confirm the
current clean HEAD is the documentation handoff commit whose ancestry contains
Session 17 commit aa76d9d692b7f906340030042c9497a073a0a511. Search current
official documentation before programming. Review, run focused tests and the
complete verify.sh, create exactly one commit named
"Add permission-bound research continuations", report the full SHA and open
uncertainty, then end the task. Do not begin Session 19 and do not push.
```
