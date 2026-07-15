# Scholium repository rules

These instructions apply to the Scholium package and all of its descendants.

## Documentation authority

Use this hierarchy; do not merge target product rules, interface rules, and current implementation evidence:

1. `Docs/PRODUCT_GUIDE.md` owns Scholium's target product role, Triptych model, workflows, terminology, and feature boundaries.
2. `Docs/DESIGN_HANDBOOK.md` owns stable interface structure, visual language, interaction principles, accessibility, exact target UI state meanings, and action labels.
3. `Docs/PRD.md` synthesizes those two authorities into release-oriented requirements, gates, risks, and traceability; it does not override either one.
4. `Docs/IMPLEMENTATION_STATUS.md` records current-to-target evidence and migration status; it is not product authority.
5. `README.md`, live construction call sites, tests, and scripts establish what is implemented and reachable now.

When target and current behavior differ, preserve the current safe behavior while implementing an explicit migration toward the Product Guide. Never describe target behavior as already implemented merely because it is canonical.

## Binding interface authority

For every user-facing interface, interaction, accessibility, or visual change:

1. Read `Docs/PRODUCT_GUIDE.md` for the affected feature and workflow.
2. Read `Docs/DESIGN_HANDBOOK.md` completely before acting.
3. Use the `scholium-apple-design` skill when it is available for product, visual, HIG, and interaction decisions.
4. Use the `scholium-swiftui-implementation` skill when it is available for material SwiftUI scenes, state, navigation, layout, presentation, AppKit mounting, or Liquid Glass implementation.
5. Read Section 10 of `Docs/DESIGN_HANDBOOK.md` before changing information architecture, user-visible state, lifecycle behavior, or action labels.
6. Verify platform-design claims against the available Apple HIG authority and the selected SDK documentation. Apple guidance does not define Scholium's Triptych, evidence, Review, Dialogue, Critique, or research-governance model.
7. Apply the accessibility requirements in `Docs/DESIGN_HANDBOOK.md` to any change affecting text, color, focus, keyboard, motion, custom controls, WebKit/AppKit, inspector, Dialogue, Critique, conflict, graph, or Canvas behavior.

`Docs/PRODUCT_GUIDE.md` is binding for target product behavior. `Docs/DESIGN_HANDBOOK.md` is binding for stable interface design and the exact target UI contract. Current code that diverges is migration debt, not an alternative product rule.

## Change discipline

- Preserve the research document as the primary interface object.
- Treat exact Markdown bytes as authoritative. Rendered HTML, parsed YAML, caches, indexes, and diagnostics are projections and must never reconstruct writable source.
- Outside explicitly changed ranges, preserve BOM, newline style, comments, unknown YAML, ordering, quoting, multiline values, and final newlines.
- Treat Scholium, Obsidian, external agents, sync tools, Finder, and other editors as concurrent filesystem participants. Never silently replace a dirty buffer after an external change.
- Keep authoritative source, researcher writing, agent-generated content, review records, and derived diagnostics visibly distinct.
- Treat neutral links and transitive paths as Connections, never as philosophical evidence.
- Store generated state outside research vaults except for the small portable `.scholium/` structure explicitly defined by the Product Guide.
- Follow the Product Guide's direct-agent-edit model. Existing-note CLI mutations require the current fingerprint; Scholium autosaves, detects conflicts, creates Before Agent Work checkpoints for Dialogue and Critique, and provides selective or complete checkpoint restore. Do not reintroduce Proposal as an authorization layer.
- Preserve menu, toolbar, keyboard, pointer, focus, accessibility, cancellation, and recovery paths.
- Do not rely on hover, drag, color, motion, secondary click, or gesture as the only route to a core task.
- Do not invent an unimplemented feature to satisfy a design request.
- Do not change a stable design decision incidentally. Record an approved change in the `Docs/DESIGN_HANDBOOK.md` decision record.
- For design-only work, do not modify application source unless the user also requests implementation or explicitly authorizes resolving a documented contradiction.
- Test only with disposable nonprivate fixture vaults, never real research vaults.

## Agent skill source

Treat the tracked `.agents/skills/` tree as the canonical source for Scholium
development skills. Do not edit the personal plugin directory or installed
cache as an independent source. After changing canonical skills, run:

```bash
./Tools/Scripts/sync-scholium-toolkit.sh --sync
./Tools/Scripts/sync-scholium-toolkit.sh --check
```

Then bump the personal plugin cachebuster and reinstall `scholium-toolkit` so
the active installed snapshot matches the repository. Never describe a skill
update as complete while these copies differ.

## Verification

For material UI implementation, verify the complete task and adjacent empty, loading, error, conflict, and recovery states with nonprivate fixtures. Test relevant menu, keyboard, pointer, focus, accessibility, minimum-width, light/dark, Increase Contrast, Reduce Transparency, and Reduce Motion behavior. Report what was verified and what remains uncertain.

## Standing UI-automation authorization

The researcher authorizes Codex to use macOS Computer Use and UI automation for Scholium development and visual QA without asking again in each task. This standing authorization is limited to:

- Xcode-built Debug or QA instances of Scholium;
- disposable copies of `TestVaults` and isolated state under temporary directories;
- launching, foregrounding, operating, resizing, and quitting those test instances; and
- capturing nonprivate screenshots and accessibility state needed to verify the interface.

Keep at most one Scholium QA process running at a time. Do not accumulate QA
windows or app copies across test journeys. Quit the process and remove its
test-owned bundle and temporary state as soon as the journey finishes.

Do not exercise UI automation against the researcher's real vaults, delete user data, package or distribute a release, change unrelated applications, or broaden the tested scope merely because this authorization exists. macOS privacy permission, tool availability, and any higher-level safety boundary still apply.
