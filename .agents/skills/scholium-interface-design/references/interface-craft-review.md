# Scholium interface-craft review

Use this reference when a Scholium interface needs systematic visual refinement
or one detail feels wrong but its cause is not yet established. It adapts a
general interface-polish method to native macOS and Scholium's authoritative
design system. It does not supply product behavior, platform rules, or permission
to edit.

## Translate the method into Scholium

- Resolve product meaning and visual identity from the live specification and
  `Design.md`; resolve platform behavior from Apple HIG and the selected SDK.
- Inspect the existing Scholium component, semantic Variables, native container,
  and complete window before proposing a new treatment.
- Preserve the live color identity and semantic resolver. It is valid to repair
  contrast, state mapping, inactive-window behavior, or accessibility adaptation;
  a polish review does not introduce another palette or restyle the product.
- Prefer SwiftUI, AppKit, SF Symbols, and system-owned interaction feedback.
  Judge a custom treatment only where the native owner cannot express the
  required Scholium meaning.
- Review a bounded WebKit region in its surrounding native document context.
  Route any editor or reader implementation to the editor-integration owner and
  preserve its source, selection, focus, composition, Undo, and scroll contract.

## Choose coverage depth

- **Quick:** one named visual detail or one small component. Inspect the primary
  path and applicable adjacent states; report at most five High or Medium
  findings.
- **Full:** the requested bounded surface across all five lenses below and its
  applicable states; report at most fifteen findings, including Low polish.

Full means complete coverage of the requested surface, not an unsolicited
whole-app audit. In either depth, inspect enough surrounding window context to
judge hierarchy. Include resting, pointer, keyboard focus, pressed, selected,
disabled, loading, empty, error, conflict, or recovery states only when the
surface can actually enter them. Check relevant narrow-width, inactive-window,
appearance, contrast, transparency, motion, and English/Chinese conditions
without manufacturing a Cartesian test matrix.

## Five craft lenses

### Typography

- Confirm that type family communicates content kind and that size, weight,
  spacing, wrapping, and truncation communicate hierarchy without competing
  with the research document.
- Inspect actual English, Simplified Chinese, mixed-script, long-label, and
  enlarged-text behavior where applicable. Do not infer line quality from a
  Latin-only static preview.
- Use tabular numerals only when changing values or aligned numeric columns
  visibly shift; do not apply them as a global style.
- Keep native-control typography system-owned and document typography owned by
  the live Appearance contract.

### Surfaces and geometry

- Distinguish a structural boundary from elevation. Keep native split dividers,
  focus rings, selection, and state boundaries when they communicate structure;
  do not replace them with decorative shadows.
- Check custom nested corners in context so radius, inset, and neighboring shape
  feel optically related. Native windows, controls, menus, sheets, and popovers
  retain platform geometry.
- Prefer optical alignment when asymmetric symbols or mixed text/symbol controls
  look geometrically centered but visually displaced. Verify at the real render
  size and in both reading directions where supported.
- Measure activation regions against the routed macOS guidance and nearby
  controls. Expanded regions must not overlap or steal text, divider, drag, or
  resize interactions.

### Icons

- Prefer the live SF Symbol and system configuration for standard actions.
  Match optical weight, scale, and alignment to adjacent interface text without
  creating a parallel icon set.
- Let native controls own hover, pressed, selected, disabled, and focus states.
  A filled or animated variant is justified only when its platform meaning and
  nonvisual state remain clear.
- Give icon-only controls an accurate accessible name; hide duplicate or
  decorative symbols. Treat directionality through Apple guidance rather than a
  blanket mirroring rule.

### Interaction feedback and motion

- Prefer system feedback. Custom feedback must communicate a real state change,
  preserve stable object identity, remain interruptible or reversible where the
  interaction is, and retain a non-motion cue.
- Keep frequent interactions quiet. Do not add entrance sequences, bounce,
  blur, parallax, or scale merely to make a control feel active.
- Inspect entry and exit together, including rapid reversal, cancellation,
  focus continuity, inactive-window behavior, and immediate Reduce Motion
  behavior.
- Route motion-only terminology, precedent triage, review, or survey to the
  interface skill’s motion guidance. Runtime observation is required for claims about feel.

### Rendering and performance

- Treat dropped frames, delayed feedback, unstable layout, repeated rendering,
  or excess layer work as performance findings only when runtime evidence or an
  existing measurement exposes them.
- Prefer the established native or WebKit rendering owner. Do not add caching,
  compositing hints, dependencies, or a shared animation layer speculatively.
- Route a reproducible latency, CPU, memory, hang, rendering, or regression
  target to the performance owner and rerun the identical scenario after a fix.

## Reject Web prescriptions

Do not carry over CSS, Tailwind, browser animation-panel steps, root font
smoothing, `currentColor`, SVG stroke tables, `box-shadow` formulas,
`AnimatePresence`, motion-library imports, `transition: all`, `will-change`, or
browser-specific text wrapping as native Scholium instructions. Fixed Web pixel
targets, press scales, blur amounts, stagger intervals, easing curves, and
outline colors are examples to discard, not values to translate mechanically.

The upstream preferences for shadows over borders, outline-versus-fill icons,
and animated icon swaps are candidates to evaluate, never defaults. Scholium's
opaque planes, fine structural rules, native controls, semantic color system,
and restrained motion remain controlling.

## Review and correction method

1. Name the researcher task, exact surface, selected interface mode, coverage
   depth, framework boundary, and current styling owner.
2. Separate observed behavior, researcher testimony, canonical rule, platform
   guidance, implementation evidence, and agent inference.
3. Inspect all five lenses. Mark an uninspected lens explicitly instead of
   implying complete coverage.
4. Consolidate repeated symptoms under one causal finding. Rank High for a
   blocked, unsafe, inaccessible, or misleading task; Medium for noticeable
   recurring friction or inconsistency; Low for bounded craft.
5. Select one coherent correction slice. Reuse, adapt, translate, minimally
   customize, or reject according to the restrained-design protocol. Multiple
   findings do not justify unrelated cleanup or a new component system.
6. Update canonical product or visual-language text only within an authorized
   Decision-recording or Implementation scope when the target itself changes;
   implementation evidence belongs in the status hierarchy.
7. Run the smallest proof capable of disproving the correction. Keep static
   inspection, compilation, deterministic tests, isolated QA, accessibility
   inspection, performance measurement, and human acceptance distinct.

## Report

State the depth, scope, framework, styling owner, and review boundary. Include a
compact coverage table for Typography, Surfaces and geometry, Icons,
Interaction feedback and motion, and Rendering and performance. Report each
finding with severity, exact location, observed behavior, actionable correction,
and researcher-visible reason. Include only real rejected candidates and end
with the selected bounded correction, verification obtained, verdict, and
unverified checks. A broad critique can contain several findings but still
returns one recommended next slice.

## Method lineage

This method selectively adapts Jakub Krehel's MIT-licensed
[`make-interfaces-feel-better`](https://github.com/jakubkrehel/make-interfaces-feel-better)
skill, especially its typography, surfaces, animation, icon, performance, and
evidence-reporting lenses. Scholium retains the cross-framework questions about
optical alignment, purposeful motion, complete states, and measured rendering.
The Web framework instructions and fixed visual recipes are deliberately not
adopted. The external source is methodological precedent only; live Scholium
authority and Apple platform guidance control every product decision.
