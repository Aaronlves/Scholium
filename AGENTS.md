# Scholium repository rules

These instructions apply to the Scholium package and all of its descendants.

## Documentation authority

Use this hierarchy; keep target rules and current implementation evidence
distinct. Each root file is the sole entry point and closed manifest for its
declared chapter set:

1. The canonical specification set rooted at `Docs/SCHOLIUM_SPEC.md` is the
   sole target authority for product role, Triptych workflows, terminology,
   feature boundaries, interface structure, Scholarly Editorialism,
   accessibility, state/action meanings, release requirements, gates, and
   active decisions. Only chapters declared by that manifest are normative.
2. The implementation-architecture set rooted at
   `Docs/IMPLEMENTATION_ARCHITECTURE.md` is the subordinate structural
   reference for modules, runtimes, state ownership, and the editor boundary.
3. The implementation-status set rooted at
   `Docs/IMPLEMENTATION_STATUS.md` records current-to-target evidence,
   migration debt, and open acceptance. It is not target authority.
4. `README.md`, live construction call sites, tests, and scripts establish what
   is implemented and reachable now.

When target and current behavior differ, preserve the specification's safety,
source-fidelity, recovery, privacy, and data-preservation requirements while
applying the bounded-cutover rule below. Never describe target behavior as
already implemented merely because it is canonical.

After changing a documentation manifest, canonical chapter, or repository
README link, run:

```bash
python3 Tools/Scripts/validate-documentation-authority.py
```

The validator requires every chapter to be declared exactly once, keeps
section IDs unique, checks local links and anchors, and rejects chapter or line
growth that defeats progressive reading.

## Binding interface authority

For every user-facing interface, interaction, accessibility, or visual change:

1. Read `Docs/SCHOLIUM_SPEC.md`, then the owning workflow chapter it routes.
2. For material interface work, read the affected interface chapter and
   `Docs/Specification/09-accessibility-and-adaptation.md` completely. Read
   `Design.md` completely only when changing
   visual language, components, materials, typography, color, layout metrics,
   interface writing, or motion. Read the unresolved-decision section in
   `Docs/Specification/10-release-and-open-decisions.md` only when the task can
   change an open target decision.
3. Use the `scholium-interface-design` skill when it is available for product,
   visual, HIG, interaction, SwiftUI, AppKit, state, lifecycle, layout, or
   presentation work. Select critique, design, decision-recording, or
   implementation mode according to the request.
4. Verify platform-design claims against the available Apple HIG authority and
   selected SDK documentation. Apple guidance does not define Scholium's
   Triptych, evidence, Review, Research Records, Critique, or research governance.
5. Apply the Accessibility and Adaptation chapter to every change affecting
   text, color, focus, keyboard, motion, custom controls, WebKit/AppKit,
   Inspector, Research Records, Critique, conflict, graph, or spatial relationships.

## Implementation and architecture choices

- Start with the existing owner and established project/platform patterns.
  Research mature comparable solutions when a new mechanism, material
  interaction, dependency, or unresolved design choice requires comparison.
  A bounded correction following a verified pattern needs no competitor survey.
  Prefer proven approaches unless Scholium's requirements justify a departure.
- Build progressively in stable end-to-end slices. First deliver the smallest
  version that is usable through the complete path, then add capability to the
  working product. A minimal version must be a sound foundation, not throwaway
  scaffolding, and immature complexity must not displace usable behavior.
- Choose the simplest implementation that fully meets the current requirements.
  Avoid abstractions, configuration, indirection, or future-facing scaffolding
  without a concrete requirement.
- Keep components modular, with explicit responsibility and concern boundaries.
  Give each behavior, state, and authority one clear owner; avoid modules that
  duplicate policy or mix unrelated responsibilities.
- Make architecture decisions for long-term evolution. Do not adopt an
  expedient design that is known to solve only the immediate case and is
  expected to require replacement later.
- Before implementing a capability or adding a dependency, evaluate the
  standard library, Apple SDK, and dependencies already used by the project.
  Read the relevant current documentation and type definitions; do not assume
  an existing library lacks a capability without verifying it.
- Prefer established, well-maintained libraries when they reduce total
  complexity or improve reliability. Add a dependency only after confirming
  that it is actively maintained, materially reduces owned complexity, and fits
  the repository's licensing, privacy, security, platform, packaging,
  source-fidelity, and long-term maintenance constraints. Do not reimplement
  common functionality without a concrete reason.
- Do not preserve backward compatibility. When a current requirement or stable
  decision replaces an earlier internal contract, update every
  repository-owned caller, test, fixture, and document in the same bounded
  change, then delete the superseded code path, adapter, alias, fallback,
  migration path, and compatibility test. Do not keep deprecated behavior
  reachable through a compatibility layer. Leave unsupported pre-production
  data byte-unchanged and nonauthorizing rather than adding a legacy product
  path; this rule does not relax exact-source, conflict, recovery, privacy, or
  data-preservation requirements.

## Change discipline

- Preserve the research document as the primary interface object.
- Treat exact Markdown bytes as authoritative. Rendered HTML, parsed YAML, caches, indexes, and diagnostics are projections and must never reconstruct writable source.
- Outside explicitly changed ranges, preserve BOM, newline style, comments, unknown YAML, ordering, quoting, multiline values, and final newlines.
- Treat Scholium, Obsidian, external agents, sync tools, Finder, and other editors as concurrent filesystem participants. Never silently replace a dirty buffer after an external change.
- Keep authoritative source, researcher writing, agent-generated content, review records, and derived diagnostics visibly distinct.
- Treat neutral links and transitive paths as Connections, never as philosophical evidence.
- Store generated state outside research vaults except for the small portable `.scholium/` structure explicitly defined by the specification.
- Follow the current Agent collaboration chapter for MCP-mediated Note
  mutations, revision checks, Agent Change evidence, and recovery. Do not
  restore retired Research Action lifecycles or approval layers from old code
  or skill guidance.
- Preserve menu, toolbar, keyboard, pointer, focus, accessibility, cancellation, and recovery paths.
- Do not rely on hover, drag, color, motion, secondary click, or gesture as the only route to a core task.
- Do not invent an unimplemented feature to satisfy a design request.
- Do not change a stable decision incidentally. For an approved change, update
  the owning canonical chapter and remove the replaced text in the same patch;
  Git owns decision history. The unresolved-decision section contains only
  questions that can still change the target, and each item is removed when
  resolved.
- For design-only work, do not modify application source unless the user also requests implementation or explicitly authorizes resolving a documented contradiction.
- Test only with disposable nonprivate fixture vaults, never real research vaults.
- Keep every SwiftPM scratch directory and Xcode DerivedData directory beneath
  the repository-local, ignored `.build/` directory. The checkout itself must
  remain outside Desktop, Documents, CloudStorage, and other File
  Provider-managed locations. Do not place build caches or indexes in `/tmp`.

## Agent skill source

Treat the repository-owned `.agents/skills/` tree as the canonical working source
for Scholium development skills and the only developer-skill discovery surface
maintained for this checkout. Track the complete toolkit, capability catalog,
references, metadata, evaluations, and validation scripts in Git so clones and
worktrees receive the same guidance. Keep generated caches and local agent state
ignored. These are developer resources, not release-shipped product Skills.
Do not duplicate project-specific packages through a personal plugin or installed
cache. Skill prose routes by responsibility rather than sibling package ID.
`.agents/skills/catalog.json` is the canonical, machine-checked mapping from
those capabilities to the current package IDs and routing-significant modes;
update it whenever either changes.

Keep development skills limited to stable triggers, authority routing,
methods, permission boundaries, invariants, and verification procedures. Put
frequently changing product rules, architecture state, implementation evidence,
active decisions, and release status in the authoritative `Docs/` hierarchy.
Skills must read those documents at task time instead of copying volatile
snapshots into skill prose.

Use `scholium-toolkit-maintenance` when it is available to audit, create,
rename, merge, validate, or evaluate these development skills. This routing
does not authorize changes to release-shipped product skills.

After changing canonical skills, run:

```bash
python3 Tools/Scripts/validate-scholium-toolkit-catalog.py
```

Run the package validator for every changed skill. Existing tasks may retain
startup discovery metadata; use a new task to verify fresh discovery when
needed, without leaving the authorized maintenance unfinished.

## Verification

For app-based testing and visual QA, open a disposable copy of the standard
500-note test Triptych at `TestVaults/`. Register its
`01-analyses`, `02-topics`, and `03-works` directories as the three respective
vaults; never register the parent as one vault. Read its `README.md` for
intentional diagnostic cases and format coverage. Preserve the source fixture
and place the test copy and isolated app state beneath `.build/`.
If the source fixture is absent, recreate it with
`python3 Tools/Scripts/generate-test-vaults.py TestVaults`.
`TestVaults/` is durable repository fixture data, not a build cache: never
delete it during build or QA cleanup, and never run mutating tests against it
directly. Keep it and its generator under version control.
`build-qa-app.sh` defaults to this source fixture and copies it into `.build/`.
Focused unit tests may retain their own minimal fixtures;
they do not require launching the app.

Keep tool output context-bounded: inspect filenames, counts, or summaries before
opening excerpts; cap verbose commands and read only relevant failures; do not
re-emit files or specification sections already loaded in the current task.

Use the lowest deterministic layer that can invalidate the claim. During
iteration, run only owning tests. Run the complete repository gate once only
after a cross-layer implementation has stabilized, or at an explicitly
identified final integration, including a release milestone. Documentation-only,
decision-recording, design-only, audit, diagnosis, presentation-only, and
single-owner changes stop at their owning validation even when they touch many
files or require repository-wide inspection. File count, broad reading scope,
or the word “final” does not establish final integration. Do not use a complete
gate as scoped evidence when unrelated worktree changes would enter it; isolate
the intended integration or report the boundary instead. Run the complete UI
suite only when the current integration or release gate explicitly requires it.

Every long UI journey must own a distinct user-boundary claim. Reuse one
existing representative journey instead of adding or running permutations,
and do not rerun a passing expensive journey after documentation-only or
formatting-only changes. On success, verification commands should print
product-level summaries and retain complete logs under `.build/`; expand only
bounded diagnostics on failure.

For material UI implementation, verify the complete task and adjacent empty, loading, error, conflict, and recovery states with nonprivate fixtures. Test relevant menu, keyboard, pointer, focus, accessibility, minimum-width, light/dark, Increase Contrast, Reduce Transparency, and Reduce Motion behavior. Report what was verified and what remains uncertain.

## Standing UI-automation authorization

The researcher authorizes Codex to use macOS Computer Use and UI automation for Scholium development and visual QA without asking again in each task. This standing authorization is limited to:

- Xcode-built Debug or QA instances of Scholium;
- disposable copies of the standard 500-note test Triptych specified above
  and isolated test state beneath `.build/`;
- launching, foregrounding, operating, resizing, and quitting those test instances; and
- capturing nonprivate screenshots and accessibility state needed to verify the interface.

Keep at most one Scholium QA process running at a time. Do not accumulate QA
windows or app copies across test journeys. Quit the process and remove its
test-owned bundle and temporary state as soon as the journey finishes.

Do not exercise UI automation against the researcher's real vaults, delete user data, package or distribute a release, change unrelated applications, or broaden the tested scope merely because this authorization exists. macOS privacy permission, tool availability, and any higher-level safety boundary still apply.
