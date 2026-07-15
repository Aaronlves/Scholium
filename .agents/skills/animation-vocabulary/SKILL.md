---
name: animation-vocabulary
description: Identify the conventional name for a motion or transition that a user describes informally. Use for reverse-lookup questions such as "what is this animation called?" and for distinguishing nearby motion terms. This skill names effects only; it does not recommend whether to use them, prescribe timing or easing, make performance claims, or supply SwiftUI, AppKit, web, or Apple HIG implementation guidance.
---

# Animation Vocabulary

Lead with the closest term and a one-sentence definition. If two terms plausibly
fit, name the best match first and contrast at most two alternatives. Mark an
approximation rather than inventing a term.

For Scholium, treat the result as vocabulary only. Route product meaning to the
Product Guide and Design Handbook, Apple-platform claims to `apple-hig`, and
native implementation to `scholium-swiftui-implementation`.

## Entrances and exits

- **Fade in / fade out** — An element appears or disappears through opacity.
- **Slide in / slide out** — An element enters or exits by translating from or toward another position.
- **Scale in / scale out** — An element enters or exits while changing size.
- **Pop in** — A scale entrance with a noticeable overshoot before settling.
- **Reveal** — Content becomes visible as a clipping or masking boundary moves.
- **Enter / exit transition** — The transition associated with insertion or removal.

## Sequence and timing

- **Keyframes** — Explicit intermediate states through which an animation progresses.
- **Interpolation / tween** — Generation of intermediate values between states.
- **Stagger** — Similar transitions begin at offset times across a group.
- **Orchestration** — Multiple transitions are timed as one coordinated sequence.
- **Delay** — Time before a transition begins.
- **Duration** — Time assigned to a duration-based transition.
- **Fill mode** — A web-animation rule governing whether endpoint styles persist outside playback.

## Movement and geometry

- **Translate** — Move along one or more axes.
- **Scale** — Change size around an anchor point.
- **Rotate** — Turn around an axis or point.
- **Skew** — Shear a shape along an axis.
- **Perspective** — A projection that changes the apparent depth of 3D transforms.
- **Transform origin / anchor** — The point around which a geometric transformation occurs.
- **Origin-aware transition** — A transition whose movement or transformation preserves its relationship to an invoking element.

## State continuity

- **Crossfade** — One state fades out while another fades in.
- **Continuity transition** — A transition that preserves orientation or identity across a state change.
- **Morph** — One shape or representation transforms continuously into another.
- **Shared-element transition** — A corresponding element moves or transforms between two layouts or views.
- **Layout animation** — A layout change is presented as continuous motion rather than an immediate jump.
- **Accordion / collapse** — A region expands or contracts to reveal or hide content.
- **Direction-aware transition** — Direction changes according to navigation or state-change direction.

## Scroll and navigation

- **Scroll reveal** — Content transitions as it enters a scroll viewport.
- **Scroll-driven animation** — Scroll progress determines animation progress.
- **Parallax** — Visual layers move at different rates to suggest depth.
- **Page transition** — Motion presented while navigating between pages or routes.
- **View transition** — A transition connecting two rendered view states.

## Feedback and manipulation

- **Hover effect** — A visual response to pointer hover.
- **Press / tap feedback** — A response presented while or after activation.
- **Hold to confirm** — Progress accumulates while activation is maintained.
- **Drag** — Direct manipulation that moves an element with an input device.
- **Drag to reorder** — Dragging changes an item's order in a collection.
- **Swipe to dismiss** — A directional drag removes or closes a surface.
- **Rubber-banding** — Resistance followed by return when movement exceeds a boundary.
- **Shake / wiggle** — Repeated short displacement, often used as feedback.
- **Ripple** — A radial response expanding from an activation point.

## Easing and physical models

- **Easing** — The mapping from elapsed time to transition progress.
- **Ease-out** — Progress begins faster and slows near the end.
- **Ease-in** — Progress begins slowly and accelerates.
- **Ease-in-out** — Progress accelerates and then decelerates.
- **Linear** — Progress changes at a constant rate.
- **Cubic-bezier** — A curve representation commonly used for web easing.
- **Spring** — Motion computed from a spring-like model rather than only a fixed timing curve.
- **Stiffness / tension** — A parameter describing the restoring force of a spring model.
- **Damping** — A parameter describing how oscillation dissipates.
- **Mass** — A parameter affecting acceleration in a physical model.
- **Bounce / overshoot** — Motion passes a target before settling.
- **Momentum** — Motion continues according to carried velocity.
- **Interruptible transition** — A running transition can retarget without first completing.

## Visual effects and diagnostics

- **Blur transition** — Blur changes during a transition.
- **Clip path** — A hard-edged clipping region controls visibility in web or vector rendering.
- **Mask** — An alpha or luminance image controls partial visibility.
- **Skeleton / shimmer** — A temporary loading representation, sometimes with moving highlight.
- **Number ticker** — Digits transition as a numeric value changes.
- **Typewriter effect** — Text is revealed incrementally as if typed.
- **Frame rate** — The number of presented frames per second.
- **Jank** — Perceptible irregularity or stutter in presented motion.
- **Dropped frame** — A frame misses its presentation deadline.
- **Reduced motion** — An accessibility preference requesting less vestibular or nonessential motion.
