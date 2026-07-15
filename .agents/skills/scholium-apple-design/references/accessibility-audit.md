# Scholium accessibility verification

Use this reference only for Scholium-specific consequences, workflow coverage,
and evidence. Load routed `apple-hig` files for Apple accessibility rules,
component semantics, measurements, contrast, typography, motion, localization,
and input conventions. Verify implementation-facing APIs in the selected Xcode
toolchain.

The Product Guide owns target workflows. Section 10 of the Design Handbook owns
exact user-visible state meanings and action labels.

## Finding priorities

- **P0:** A researcher cannot complete a core reading, navigation, editing,
  review, Dialogue, Critique, checkpoint, conflict, or save task, or could lose
  or misidentify work or source authority.
- **P1:** Research authority, provenance, focus, state, or recovery is materially
  unclear or difficult to reach.
- **P2:** A bounded Scholium workflow has weaker semantics, ordering, scaling,
  localization, or consistency without blocking task completion.

Each finding must name the researcher task, framework boundary, user impact,
expected result, authority, and verification evidence. A clean accessibility
tree or presence of a label is not proof that the task works.

## Research-document invariants

- Keep primary-source evidence, researcher writing, derived state, and agent
  content distinguishable in names, structure, reading order, and state.
- Preserve exact Markdown meaning across Read, Live Preview, and Source.
- Preserve useful selection, focus, and nearby semantic location across mode
  changes and projection refreshes.
- Make document structure and relationships navigable without implying that a
  Connection is philosophical evidence.
- Preserve mixed-language text, punctuation, paragraph direction, insertion,
  selection, and source-range identity.

## Workflow invariants

- Expose every applicable Section 10 action under its exact visible name.
- Keep Dialogue Comments, agent Responses, Human Review, attributed Critique,
  Note History, checkpoints, conflicts, restore, save, and derived refresh
  semantically distinct.
- Preserve unsaved or conflicted work after failure and provide a direct route
  to the relevant recovery action.
- Preserve note selection and task context when focus moves among the sidebar,
  document, inspector, Search, Dialogue, Critique, and History.
- Provide a source-anchored list or table equivalent for graph or Canvas
  relationships so spatial layout never becomes evidential meaning.

## Evidence matrix

Use nonprivate fixtures and record only applicable rows.

| Dimension | Scholium exercise |
| --- | --- |
| Assistive technology | Complete the affected task and inspect research-authority labels, structure, values, actions, order, and announcements. |
| Keyboard and menus | Complete the task through the relevant commands, focus path, cancellation, and non-drag alternative. |
| Scaling and windows | Exercise the documented minimum, a large window, and the Product Guide's reader/editor scaling target. |
| Appearance and motion | Exercise the relevant system accessibility appearances and confirm that Scholium state remains legible. |
| Language | Exercise Chinese or mixed scripts, long localized labels, and directionality where relevant. |
| State | Exercise applicable ready, empty, loading, unavailable, stale, conflict, error, completion, and recovery states. |
| Framework | Verify every reachable SwiftUI, AppKit/TextKit, WebKit, graph, or Canvas boundary involved in the task. |
| Persistence | Close and reopen relevant surfaces; verify focus, selection, scroll, disclosure, and unsaved-work recovery. |

Use Apple-provided inspection tools as structural evidence, then verify the
actual task with the relevant assistive technology. Automation supplements but
does not replace task completion.
