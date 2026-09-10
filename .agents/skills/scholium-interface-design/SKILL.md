---
name: scholium-interface-design
description: "Critique, design, record, or implement Scholium's native macOS interface. Use for SwiftUI/AppKit layout, navigation, focus, accessibility, visual polish, or motion; route interaction verification to Xcode workflow."
---

# Scholium Interface Design

Translate ordinary researcher language into professional native-interface
judgment. Keep the research document primary and keep target, current behavior,
implementation, automation, and human acceptance distinct.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
Read the affected workflow, interface, accessibility, and Design authority as
required by `AGENTS.md`; Apple HIG and selected SDKs support platform claims.

## Modes

- **Critique:** inspect and prioritize; remain read-only and return one
  researcher-visible recommendation.
- **Design:** propose an unapproved behavior and presentation contract; edit no
  specification or application source.
- **Decision recording:** after explicit approval, update only the owning
  canonical decision and its replaced text.
- **Implementation:** carry out the requested build or repair against the target
  authority, with focused proof. The implementation request authorizes routine
  choices; ask only for an unresolved material product decision. Human and
  release acceptance remain distinct.

## Method

For motion terminology, a recording, or a bounded transition review, start with
[motion guidance](references/motion-review.md). A terminology-only request needs
no complete-window inspection or implementation loop.

1. Select the mode from the user's requested side effects, frame the researcher
   task, and inspect the reachable workflow in complete window context.
2. For Critique or Design, load
   [professional design practice](references/professional-design-practice.md).
   Before material feature, workflow, component, or system design, apply the
   [restrained-design and established-solution protocol](../scholium-toolkit-maintenance/references/restrained-design-and-solution-research.md).
3. For a visual-polish request, a broad presentation review, or a correction
   involving typography, surfaces, geometry, icons, feedback, or fine motion,
   load the [Scholium interface-craft review](references/interface-craft-review.md).
   Use its quick or full coverage depth inside the selected permission mode;
   those depths are not additional modes.
4. For Implementation, load the
   [SwiftUI and native implementation loop](references/swiftui-implementation-loop.md).
   When SwiftUI and AppKit share a region, also apply the
   [native-container diagnosis](references/native-window-boundary-debugging.md).
5. Load another conditional reference only when needed:
   [component/state system](references/component-state-presentation-system.md),
   [accessibility verification](references/accessibility-audit.md).
6. Define the proof capable of invalidating the selected mode's claim. Route
   Xcode toolchain/build/diagnostic/QA orchestration to the available Xcode
   workflow capability while keeping local `AGENTS.md` and the toolkit catalog
   authoritative. Route deterministic application journeys and genuine human
   judgment to Xcode workflow's interaction verification.
7. Report only the selected mode's output; do not promote design inspection,
   compilation, or automation into a stronger acceptance class.

## Invariants

- Prefer native behavior and existing Scholium structure when they satisfy the
  task. Do not replace a stable framework boundary because another API is newer.
- Treat the live `Design.md` as visual-language authority. Craft work may repair
  semantic color use, contrast, adaptation, or optical treatment, but it does
  not replace Scholium's color identity, introduce a parallel palette, or copy
  raw values from an external reference into feature code.
- One mutable fact has one owner. A reusable presentation layer owns no domain,
  document, authorization, navigation, or operation lifecycle.
- In a hybrid region, the native container and declarative content must not
  co-own geometry, identity or reuse, transient interaction state, or lifecycle;
  their coordinator translates changes and owns no competing truth.
- Preserve exact source, buffers, selection, focus, Undo, marked text, scroll,
  save/conflict state, window isolation, cancellation, and recovery.
- Keep source, researcher writing, agent content, review records, and derived
  diagnostics visibly and accessibly distinct.
- Preserve menu, keyboard, pointer, focus, and accessibility routes; no hover,
  drag, color, motion, gesture, or secondary click is the sole core path.

Lead with the researcher-visible consequence. State the selected mode,
controlling authority, owner, proof obtained, and remaining decision or
uncertainty.
