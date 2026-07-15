# Scholium accessibility audit

Use this reference only for Scholium-specific accessibility risks and
verification. Use `apple-hig` as the authority for Apple accessibility,
VoiceOver, platform measurements, component behavior, contrast, typography,
motion, localization, and input conventions. Verify implementation-facing APIs
in the selected Xcode installation's Developer Documentation.

`Docs/PRODUCT_GUIDE.md` owns target workflows. Section 10 of
`Docs/DESIGN_HANDBOOK.md` owns exact user-visible state meanings and action
labels. Proposal and Agent Review checks apply only to current-build
compatibility until their migration is complete.

## Priorities

- **P0:** A core reading, navigation, editing, review, Dialogue, Critique,
  checkpoint, conflict, or save task cannot be completed with VoiceOver or the
  keyboard; work or source identity can be lost or misread.
- **P1:** Research authority, provenance, state, focus, or recovery is materially
  unclear or difficult to reach.
- **P2:** Semantics, announcements, ordering, scaling, localization, or
  consistency can be improved without blocking the task.

Each finding must name the affected researcher task, framework boundary, user
impact, expected result, and verification evidence. A label, trait, or clean
automated tree is not proof that the task works.

## General control semantics

- Prefer semantic `Button`, `Menu`, and `Label` controls for actions. Use a gesture recognizer only when location or tap-count information is required; otherwise expose the equivalent action and accessibility trait.
- Give icon-only controls a meaningful textual accessibility label, and hide decorative images from assistive technologies. Do not make color or motion the sole state cue; honor the platform's differentiate-without-color and Reduce Motion settings.
- Use system text styles or equivalent scaling rather than fixed text sizes, and verify labels, controls, and research content at the large-size cases in the verification matrix.

## Research-document boundaries

- Keep primary-source evidence, researcher writing, derived state, and agent
  content distinguishable through names, headings, reading order, and state.
- Preserve the same exact Markdown meaning across Read, Live Preview, and
  Source. Projection must not make the accessible value deceptively differ
  from editable source.
- Preserve useful selection, focus, and nearby semantic location when switching
  document modes or refreshing rendered content.
- Expose headings, links, lists, quotations, code, tables, citations, and
  relationships as navigable structure or provide an equivalent representation.
- Preserve mixed-language text, paragraph direction, punctuation, insertion,
  selection, and exact source ranges.

## Workflow and state

- Make every applicable Section 10 action reachable under its exact visible
  name. A consequential or destructive action must not become the accidental
  default.
- Keep Dialogue Comments and agent Responses distinguishable without exposing
  hidden prompt mechanics.
- Make Human Review, attributed Critique, Note History, checkpoints, conflicts,
  restore, save, and derived refresh semantically distinct.
- Keep unsaved or conflicted work available after failure. Move focus to a
  persistent explanation or announce it with a direct route to recovery.
- Announce ordinary successful autosave sparingly; announce persistent conflict,
  failure, stale state, and recovery-relevant changes clearly.
- Keep app-controlled reader and editor scaling usable to at least 200% without
  altering source text.

## Navigation and relations

- Preserve note selection when focus moves among sidebar, document, inspector,
  Search, Dialogue, Critique, or History.
- Describe every relationship with subject, predicate, object, provenance, and
  resolution state where relevant; never rely on arrow direction, color, or
  spatial proximity alone.
- Provide a source-anchored, keyboard-accessible list or table equivalent for
  every graph or Canvas relationship view.
- Provide keyboard or menu alternatives for drag, hover, secondary click, and
  custom gestures.

## Verification matrix

Run the applicable rows with nonprivate fixtures and record results.

| Dimension | Scholium exercise |
| --- | --- |
| VoiceOver | Complete the affected task; inspect research-authority labels, structure, values, actions, reading order, and announcements. |
| Keyboard | Complete it with menus, shortcuts, focus traversal, Return, Space, Escape, and non-drag alternatives. |
| Scaling | Test the minimum and a large window plus at least 200% reader/editor text. |
| Appearance | Test light, dark, Increase Contrast, Reduce Transparency, accent changes, and non-color state cues. |
| Motion | Enable Reduce Motion and verify state continuity without required animation. |
| Language | Test Chinese, mixed scripts, long pseudo-localization, and right-to-left chrome where applicable. |
| State | Exercise applicable ready, empty, loading, unavailable, stale, conflict, error, completion, and recovery states. |
| Framework | Verify each reachable SwiftUI, AppKit/TextKit, WebKit, and Canvas boundary separately. |
| Persistence | Close and reopen relevant sheets or windows; verify focus, selection, scroll, disclosure, and unsaved-work recovery. |

Use Xcode Accessibility Inspector for structural evidence, then verify the task
with the actual assistive technology. Automation supplements but does not
replace task completion.
