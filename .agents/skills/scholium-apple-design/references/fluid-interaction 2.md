# Fluid interaction and visual craft
This reference integrates compatible heuristics from the supplied,
web-oriented `apple-design` draft into Scholium's native macOS design review.
It is a secondary reasoning aid. It is not an Apple HIG source, does not define
Scholium product behavior, and does not establish implementation-facing API
availability. Route HIG claims to `apple-hig`; route API claims to the selected
Xcode installation's Developer Documentation, SDK, and compiler.

## When to use this reference

Load it when a task involves:

- gesture-driven movement, drag and drop, resizing, scrolling, sheets, or
  dismissals;
- interruptible transitions, momentum, snapping, rubber-banding, or latency;
- Liquid Glass, translucency, depth, or material transitions;
- typography, text scaling, optical hierarchy, or mixed-script layout; or
- sound, haptics, reduced motion, reduced transparency, Increase Contrast, or
  other multimodal feedback.

The Product Guide and Design Handbook still decide what the researcher is
doing, what a state means, where it belongs, and which exact action label is
valid. This reference only helps evaluate the quality of the interaction.

## 1. Response and direct manipulation

- Give feedback when the interaction begins, not only after release or commit.
  For continuous manipulation, keep the presentation continuous with the input.
- Preserve the user's grab offset. Do not make a dragged object jump to its
  center or to a new logical position when the pointer or trackpad first takes
  hold.
- Keep pointer or gesture tracking alive for the whole interaction when the
  native API supports capture. Use the platform's standard pointer, drag, menu,
  keyboard, and accessibility routes rather than inventing a web recognizer.
- Remove avoidable debounces, timers, transition locks, and other latency from
  the direct-manipulation path. If a delay is required by product semantics,
  make the pending state legible and cancellable where appropriate.

For macOS, keyboard and pointer completion must remain available even when a
gesture is supported. A drag, hover, force click, or custom gesture is never
the only route to a core Scholium task.

## 2. Interruptible motion

The key test is whether the researcher can change their mind while a surface
is moving. Retarget from the current presented value, not a stale destination;
avoid visible jumps between the logical state and what is on screen; and keep
input enabled unless the product state genuinely requires modality.

Use spring-like behavior where physical continuity helps, but reason in terms
of behavior rather than blindly copying a parameter table:

- ordinary appearance, dismissal, and repositioning should settle calmly;
- overshoot belongs to an interaction that carried momentum, not to every
  menu, status change, or confirmation;
- a two-axis movement should not visibly lose synchronization when its axes
  have different input or release velocities; and
- a reverse gesture should not produce a sudden velocity discontinuity.

Exact damping, response, duration, animation curves, and API semantics require
verification against current Apple guidance and the selected SDK. The supplied
draft's numeric spring defaults are not a Scholium contract.

## 3. Momentum, boundaries, and spatial continuity

When an interaction has a real release velocity, a snap or resting destination
may account for where the gesture is going rather than only where it stopped.
Use this only for a genuine physical interaction, document the chosen behavior,
and verify it with the actual input device. Do not import a browser or textbook
projection formula as an Apple rule.

For reversible or spatially anchored transitions:

- keep entry and exit paths intelligible and related;
- preserve the relationship between a popover, sheet, inspector, or menu and
  the control that opened it;
- use progressive resistance at a meaningful boundary rather than making a
  valid drag appear frozen; and
- make the destination, cancellation path, and failure result visible without
  relying on motion alone.

These principles must remain subordinate to the handbook's document-first
topology, exact state/action contract, conflict recovery, and minimum-width
requirements.

## 4. Materials and depth

Materials should communicate hierarchy and relationship. For Scholium:

- keep dense Markdown, source, diff, diagnostic, and other research-sensitive
  surfaces opaque or otherwise calm enough to preserve legibility;
- use Liquid Glass primarily for the navigation and control roles allowed by
  `DESIGN_HANDBOOK.md`, not as a decorative layer over the document;
- avoid stacking translucent surfaces when it reduces text or state clarity;
- use depth, blur, scale, or shadow only when they explain separation,
  continuity, or focus; and
- provide a clear solid or higher-contrast presentation when Reduce
  Transparency or Increase Contrast is enabled.

If a material transition is proposed, review its entry and exit together. A
surface that only fades while its hierarchy changes may read as an arbitrary
opacity effect; a native material transition should make arrival, focus, and
dismissal understandable without distracting from the research object.

Do not translate `backdrop-filter`, fixed CSS translucency values, or browser
compositing assumptions into SwiftUI/AppKit implementation guidance.

## 5. Typography and visual craft

Evaluate typography as a system of size, weight, tracking, leading, and
available width. Larger display text may need tighter tracking; body text needs
comfortable leading; dense technical text must remain readable at large sizes
and in mixed English/Chinese or other scripts. Test long labels and right-to-
left chrome where applicable.

Use system text styles and the platform's scaling behavior where the handbook
does not specify a Scholium choice. Where it does specify one, follow the
handbook: current Scholium typography decisions include system interface
typography, Alegreya for prose, Victor Mono for exact/source text, and a 12pt
document body. Do not replace those decisions with the supplied draft's CSS
font stack or fixed web values.

Every visual detail should earn its cost in attention. Prefer clear grouping,
specific labels, stable mapping between a control and what it changes, and a
calm hierarchy over novelty. A polished interaction is one whose purpose,
agency, familiarity, flexibility, simplicity, and craft are legible in use;
these are review prompts here, not additional Apple or Scholium policy.

## 6. Multimodal feedback

Visual feedback, sound, and haptics should share a clear causal event and
should not compete with one another. Add them only when they communicate a
meaningful status, completion, warning, error, commit, or snap. Preserve a
visual/textual equivalent for people who cannot hear or feel the feedback, and
verify any API behavior in the selected SDK.

Scholium must not add sound or haptics merely to make a research workflow feel
more lively. Source authority, focus, conflict, save, review, Dialogue,
Critique, and recovery remain explicit in text and standard controls.

## 7. Reduced motion and accessibility

Reduced motion is a change in how continuity is communicated, not permission
to remove necessary feedback. When Reduce Motion is enabled:

- replace large travel, parallax, elastic overshoot, and repetitive motion with
  a short cross-fade, static state change, or other non-vestibular equivalent;
- keep direct manipulation understandable while avoiding unnecessary depth or
  scale effects; and
- ensure focus, selection, completion, error, conflict, and recovery remain
  legible without animation.

Also verify Reduce Transparency, Increase Contrast, light/dark appearance,
200% text scaling, keyboard-only operation, VoiceOver, mixed scripts, and
non-drag alternatives. Do not use color, motion, sound, hover, secondary click,
or a custom gesture as the only state or action signal. Apply the priorities and
evidence requirements in `accessibility-audit.md` and the routed `apple-hig`
files.

## Review checklist

For a motion-sensitive design decision, record:

1. the researcher task and the object being manipulated;
2. the input-start feedback and any required latency;
3. the current presented value used when retargeting or interrupting;
4. whether release velocity or boundary resistance represents a real gesture;
5. the entry, exit, cancellation, failure, and recovery paths;
6. the semantic/textual equivalent when motion is unavailable;
7. the material and typography roles, including scaling and appearance modes;
8. the keyboard, pointer, focus, VoiceOver, and menu alternatives; and
9. the exact verification performed and any remaining uncertainty.

## Do not carry over from the web draft

The following are source-specific implementation details, not Scholium rules:

- CSS `transition`, `@keyframes`, `backdrop-filter`, `@media` queries,
  `requestAnimationFrame`, Pointer Events, `setPointerCapture`, and
  `Vibration API`;
- Motion/Framer Motion option names and CSS pixel, `rem`, or `em` constants;
- the source's spring, deceleration, rubber-band, timing, and hit-padding
  numbers without current HIG/SDK verification; and
- claims that a quoted WWDC talk or the supplied draft alone establishes a
  current Apple platform requirement.
