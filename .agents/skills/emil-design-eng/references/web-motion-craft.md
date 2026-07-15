# Web motion craft reference

This is the single shared web-motion reference for `emil-design-eng`,
`improve-animations`, and `review-animations`. It distills an attributed craft
perspective from Emil Kowalski's published work. It is not a platform standard,
an Apple HIG source, a Scholium product contract, or native SwiftUI/AppKit
guidance.

## Decision sequence

1. Identify the user task and the state change.
2. Ask whether motion explains continuity, relationship, feedback, or progress.
3. Estimate frequency. Frequent actions generally need less motion, but input
   modality alone does not decide whether a shared state transition animates.
4. Reuse the product's existing motion tokens before proposing new values.
5. Verify the result in context; code inspection cannot establish feel.

Deleting an animation is appropriate when it has no explanatory or feedback
role, delays a frequent task, obscures state, or creates accessibility or
performance cost without corresponding value.

## Timing and easing heuristics

Use these as starting ranges for web interfaces, not pass/fail thresholds:

| Element | Starting range |
| --- | --- |
| Press feedback | 100–160ms |
| Tooltip or small popover | 125–200ms |
| Dropdown or select | 150–250ms |
| Modal or drawer | 200–500ms, with the longer end justified by distance and content |

- Entrances and exits often benefit from a responsive ease-out.
- Movement between visible positions often benefits from ease-in-out.
- Constant-rate progress or marquees may require linear motion.
- Avoid declaring any easing family universally invalid; inspect the actual
  curve, duration, distance, context, and product tokens.
- Custom cubic-beziers are optional web implementation choices, not a quality
  requirement and never an Apple attribution.

## Origin, continuity, and interruption

- Relate anchored surfaces to the control that invoked them.
- Avoid entrances whose scale or travel makes the source relationship unclear.
- Retarget reversible or rapidly repeated transitions from the currently
  presented value.
- Use a spring only when physical continuity or carried velocity helps explain
  the interaction. Avoid decorative overshoot in calm or consequential flows.
- Keep entry, exit, cancellation, and reversal spatially coherent.

## Web performance profile

Apply this section only to browser-rendered code:

- Prefer bounded transition properties over `transition: all`.
- Prefer transform and opacity when they express the design without forcing
  repeated layout or paint, but do not treat every layout animation as a defect.
- Measure before asserting that a library shorthand, CSS variable, filter,
  keyframe, or JavaScript animation causes dropped frames.
- Use browser performance tooling under representative load; a token match is
  only a review prompt.
- Choose CSS, WAAPI, or JavaScript according to required dynamism,
  interruptibility, and measured runtime behavior.

## Web accessibility profile

- Honor `prefers-reduced-motion` with a non-vestibular equivalent that preserves
  necessary feedback and state continuity.
- Gate hover-only effects for devices that genuinely support hover, and keep a
  non-hover route to every core action.
- Do not make motion, color, sound, or pointer position the sole state signal.
- Verify keyboard operation, focus continuity, zoom, contrast, and assistive
  technology behavior in the actual interface.

## Review evidence

When feel or performance is uncertain, require one or more of:

- slow-motion or frame-by-frame capture;
- browser animation and performance tooling;
- representative device and input testing;
- reduced-motion and keyboard journeys; and
- comparison with existing product motion tokens.

Report the observed problem, evidence, consequence, proposed adjustment, and
remaining uncertainty. Do not turn a heuristic range into a blocking defect
without context-specific evidence.
