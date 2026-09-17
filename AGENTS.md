# Scholium repository rules

These instructions apply to this package and all descendants.

## Task execution and collaboration

Execution guidance adapts [OpenAI's prompting guidance](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra#prompting-best-practices),
checked on 2026-09-14; it selects no runtime model or API configuration.

- Complete implementation through scoped verification, reviewable results and
  test-owned cleanup. Respect discussion, diagnosis and design-only scope.
- The researcher owns intent, material tradeoffs and experiential acceptance.
  Resolve routine choices from owning documents and live code; ask only for
  missing facts or material researcher decisions. Do not invent research facts
  or silently settle unresolved product decisions.
- Retain existing authorization and continue independent authorized work while
  a decision is pending. Prepare reviewable work before required final approval.
  Coding does not authorize publication, distribution or real-vault use.
- User instructions override skills, subject to higher-priority rules. Check scope
  and authorization before treating a skill as blocking; link and quote the rule
  and distinguish it from interpretation.
- Corrections and status questions steer rather than restart work. Preserve completed
  work and obligations across turns and compaction. On resumption, refresh objective,
  authorization, worktree, proof, decisions and cleanup against live evidence.
  Task context is not product authority; keep it out of canonical documents and skills.
- Select the narrow owner; add capabilities only for distinct contracts or proof.
  For external claims follow the conditional
  [live-source research policy](.agents/skills/scholium-toolkit-maintenance/references/live-source-research.md).

### Parallel work

Use subagents for bounded independent work that improves quality or latency while
the parent advances useful work. Keep small sequential changes local. Assign clear
questions or file ownership, authority and expected evidence; avoid overlapping edits
and duplicate tests. The parent checks, integrates and owns completion. Delegation
expands neither authorization nor verification scope; messages remain readable.

### Communication

Lead with concise results or decisions. Use lists and tables for useful comparison, not
repeated summaries or jargon. Give brief updates during longer work. Report the
change, validation and uncertainty; distinguish source evidence, inference,
automated checks and human acceptance without sacrificing fidelity.

## Documentation authority

Keep target and implementation evidence distinct. Each root is the sole entry
point and closed chapter manifest:

1. `Docs/SCHOLIUM_SPEC.md` alone owns target product role, Triptych workflows,
   terminology, feature/interface boundaries, Scholarly Editorialism,
   accessibility, state/action meanings, release requirements/gates and active
   decisions. Only declared chapters are normative.
2. `Docs/IMPLEMENTATION_ARCHITECTURE.md` is the subordinate structural reference
   for modules, runtimes, state owners and editor boundaries.
3. `Docs/IMPLEMENTATION_STATUS.md` records current-to-target evidence, migration
   debt and open acceptance, not target authority.
4. README, live construction/call sites, tests and scripts establish reachability.

Divergence never relaxes source-fidelity, safety, recovery, privacy or preservation;
apply bounded cutover below. Canonical target prose does not prove implementation.

Maintain prose only when it prevents a concrete decision error, adds a contract,
cross-boundary context, effective proof or unresolved work rather than repeating
an existing owner or local code inventory, and has one named owner.
Normal implementation does not require updating every document: change only an
affected contract, structural boundary, open item or effective proof. Replace
superseded wording rather than append; clear completed Open Work and superseded
proof while retaining effective baselines and necessary provenance. Git owns
history.

The existing documentation validator bounds Architecture, Status and developer
instructions as groups. Do not raise/evade budgets, create overflow files or relax
checks without explicit researcher instruction. New rules, authority-owner shifts
or material documentation growth receive a bounded independent diff review;
small edits do not automatically require it. Add no governance document, review
log or periodic ceremony.

After changing a manifest, canonical chapter, developer instruction or README link,
run:

```bash
python3 Tools/Scripts/validate-documentation-authority.py
```

It checks closed declaration, unique section IDs, links/anchors and progressive
reading budgets. Structural validation grants no semantic edit permission.

## Binding interface authority

For every user-facing interface, interaction, accessibility or visual change:

1. Read `Docs/SCHOLIUM_SPEC.md` and its owning workflow chapter.
2. For material work, read the affected interface chapter and
   `Docs/Specification/09-accessibility-and-adaptation.md` completely. Read
   `Design.md` completely only for visual language, components, materials,
   typography, color, metrics, writing or motion. Read unresolved decisions in
   `Docs/Specification/10-release-and-open-decisions.md` only when the task can
   change an open target decision.
3. Use available `scholium-interface-design` for product, visual, HIG, interaction,
   SwiftUI/AppKit, state, lifecycle, layout or presentation work in the requested
   critique/design/decision-recording/implementation mode.
4. Verify platform claims against Apple HIG and selected SDK documentation; Apple
   does not own Triptych, evidence, Review, Critique or research governance.
5. Apply Accessibility and Adaptation to text, color, focus, keyboard, motion,
   custom controls, WebKit/AppKit, Inspector, Critique, conflict, graph and spatial
   changes.

## Design document change boundary

`Design.md` is a small stable global charter, not a feature specification. Leave
it unchanged during routine feature, implementation, bug-fix, visual-polish,
acceptance and status work. Only an explicit researcher request to change global
principles or identity authorizes editing; feature-design requests or local
discrepancies do not. Features belong to workflow/interface chapters, mechanisms
to Architecture, defaults to source and proof to Status.

Do not add feature examples, control recipes, inventories, state tables, numeric
layout/opacity/timing, API snippets, exceptions or work logs. Replace authorized
principles and remove superseded wording, never append qualifications. Create no
second global design file or overflow appendix.

The validator fixes Design's section set and ceilings of 140 lines and 1,100 words,
rejecting detailed subheadings, tables, code blocks and local geometry/timing.
Limits are not filling targets. Do not weaken/bypass checks or add allowed sections
for routine work; changing this boundary requires explicit researcher instruction.
Passing proves structure, not relevance or permission. Validate authorized edits.
Design alone owns global visual boundaries; feature chapters/skills reference it
without further branded surfaces or exceptions.

## Implementation and architecture choices

- Start with the existing owner and verified project/platform patterns. Research
  mature comparables for new mechanisms, interactions, dependencies or unresolved
  choices, not each bounded correction.
- Build stable end-to-end slices: the smallest usable version is a durable
  foundation, not throwaway scaffolding. Use the simplest complete solution with
  no abstraction, configuration or indirection without a concrete need.
- Give behavior, state and authority one owner. Keep concerns modular, avoiding
  duplicate policy and knowingly short-lived architecture.
- Before implementing a capability or adding a dependency, evaluate the standard
  library, Apple SDK and existing dependencies using current docs and type definitions.
  Never assume an
  existing library lacks a capability without checking.
- Prefer established maintained libraries that reduce owned complexity or improve
  reliability. New dependencies must be actively maintained, materially reduce
  complexity and fit licensing, privacy, security, platform, packaging, fidelity
  and long-term maintenance. Reimplement common functionality only for concrete
  reasons.
- Preserve no backward compatibility. Replace internal contracts across all owned
  callers, tests, fixtures and affected documents in one bounded change; delete
  superseded paths, adapters, aliases, fallbacks, migration paths and compatibility tests.
  Unsupported preproduction data remains byte-unchanged and nonauthorizing, not
  reachable through legacy product paths. Exact-source, conflict, recovery, privacy
  and preservation requirements still apply.

## Change discipline

- Preserve the research document as the primary interface object.
- Exact Markdown bytes are source authority; HTML, parsed YAML, caches,
  indexes and diagnostics never reconstruct it. Outside changed ranges preserve
  BOM, newline/final-newline style, comments, unknown YAML, order, quoting and
  multiline values.
- Scholium, Obsidian, agents, sync, Finder and other editors are concurrent
  filesystem participants. Never silently replace a dirty buffer after external change.
- Keep source, researcher writing, Agent content, review records and diagnostics
  visibly distinct. Neutral links/transitive paths are Connections, not evidence.
- Generated state stays outside vaults except the specification's portable
  `.scholium/` structure.
- Follow current Agent collaboration for MCP Note mutations, revisions, Agent
  Change evidence and recovery; restore no retired Research Action lifecycle or
  approval layer from old code/skills.
- Preserve menu, toolbar, keyboard, pointer, focus, accessibility, cancellation
  and recovery paths. Hover/drag/color/motion/secondary click/gestures cannot be
  the sole route to a core task. Invent no unimplemented feature for design work.
- Never incidentally change a stable decision. Approved changes replace owning
  canonical wording in the same patch; resolved questions leave the unresolved
  section. Git owns decision history.
- Design-only work changes no application source without implementation authority
  or explicit permission to resolve a documented contradiction.
- Test only disposable nonprivate fixtures, never real research vaults.
- SwiftPM scratch/Xcode DerivedData stays under repository-local ignored
  `.build/`. No build caches or indexes go in `/tmp`. The checkout remains outside
  Desktop, Documents, CloudStorage and other File Provider-managed locations.

## Agent skill source

`.agents/skills/` is this checkout's sole canonical developer-toolkit source and
discovery surface, not release product Skills. Track catalog, references, metadata,
evaluations and validators in Git; ignore caches and local state. Do not duplicate
packages through personal plugins or installed caches. Prose routes by responsibility;
`.agents/skills/catalog.json` maps capabilities to package IDs/significant modes
and changes with either.

Skills retain stable triggers, routing, methods, permission boundaries, invariants
and verification only. Volatile product rules, architecture, evidence, decisions
and release state belong to owning Docs, read at task time. Repository-wide rules
live here, not a second shared contract loaded/repeated by every skill.

Use available `scholium-toolkit-maintenance` for developer-skill audit, creation,
rename, merge, validation or evaluation; it grants no authority over release-shipped Skills.
After canonical skill changes run:

```bash
python3 Tools/Scripts/validate-scholium-toolkit-catalog.py
```

Run each changed package's validator. A new task may verify fresh discovery when
startup metadata is stale; finish authorized maintenance regardless.

## Verification

App/visual QA uses a disposable copy of the standard 500-note `TestVaults/`
Triptych. Read its README; register `01-analyses`, `02-topics`, `03-works`
separately, never the parent as one vault. Preserve the source; copies and isolated
state stay under `.build/`. If absent, recreate with
`python3 Tools/Scripts/generate-test-vaults.py TestVaults`.
Fixture/generator are durable version-controlled data, never cleanup targets or
direct mutating-test inputs. `build-qa-app.sh` defaults to copying this fixture.
Focused units may use minimal fixtures without launching the App.

Bound tool output: inspect filenames/counts/summaries first, cap verbosity/read
relevant failures and do not re-emit already loaded files/specifications.
Use the lowest deterministic layer that can invalidate a claim; iterate with
owning tests. Add tests for meaningful risks, not restatements. Stop after scoped
checks unless a new change, failure, concern or required gate justifies more.

Run the complete repository gate once only after stabilized cross-layer
implementation or explicitly identified integration/release. Documentation,
decision, design, audit, diagnosis, presentation and single-owner work stop at
owning validation despite file count/broad inspection; “final” does not establish
integration. Unrelated changes cannot enter scoped gate evidence: isolate or
report the boundary. Full UI suites run only when the current gate requires them.

Each long UI journey owns a distinct user-boundary claim. Reuse a representative
journey, not permutations; do not repeat passing expensive journeys for prose or
format-only edits. Successful checks print product summaries and retain full logs
under `.build/`; expand bounded diagnostics only on failure.

Material UI verification covers complete tasks and adjacent empty/loading/error/
conflict/recovery with nonprivate fixtures. Check relevant menu, keyboard, pointer,
focus, accessibility, minimum width, light/dark, Increase Contrast, Reduce
Transparency and Reduce Motion. Report verified scope and uncertainty.

## Standing UI-automation authorization

Standing authorization permits macOS Computer Use/UI automation without repeated
permission only for Xcode-built Scholium Debug/QA instances, disposable standard
500-note Triptych copies and isolated `.build/` state. It covers launching,
foregrounding, operation, resizing, quitting and nonprivate screenshot/accessibility
capture for verification.

Run at most one QA process; accumulate no windows/copies across journeys. Quit and
remove the test-owned bundle/temporary state when finished. This authorizes no real-
vault automation, user-data deletion, release packaging/distribution, unrelated
application changes or scope expansion. Privacy permissions, tool availability and
higher safety boundaries still apply.
