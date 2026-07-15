# Scholium motion-sensitive workflow review

Use this reference for Scholium-specific review questions when a workflow uses
dragging, resizing, scrolling, interruption, spatial transitions, or other
motion-sensitive interaction. It does not supply Apple rules, API behavior,
timing values, spring parameters, or product states. Load `apple-hig` and the
selected Xcode documentation for those claims.

## Bind the research task

Record:

- the research object and target workflow;
- the exact Product Guide and Design Handbook state or action;
- every supported input and accessibility route;
- entry, exit, cancellation, failure, conflict, and recovery states; and
- the current implementation evidence.

Do not allow motion to invent a state, relabel an action, obscure authorship, or
turn a Connection into evidence.

## Direct manipulation

Check that the presented object remains the same research object throughout the
interaction. Verify that beginning, continuing, cancelling, and completing the
manipulation do not lose selection, focus, provenance, source identity, dirty
buffer state, or conflict information.

If a drag or gesture is supported, verify the handbook-required keyboard,
pointer, menu, and accessibility alternatives. The gesture is never the only
route to a core research task.

## Interruption and reversal

Exercise repeated activation, reversal while moving, cancellation, and an
external state change during the transition. Confirm that the visible state and
the authoritative document or workflow state do not diverge.

Treat timing, curves, damping, velocity handling, and framework behavior as
unverified until established through routed Apple guidance, selected-SDK
documentation, and runtime evidence. Do not import web constants or browser
mechanisms into native code.

## Spatial and material interpretation

Check that motion preserves the handbook-defined relationship among the
Triptych, document, inspector, Dialogue, Critique, History, and invoking
controls. Dense research content, source, diffs, diagnostics, and metadata must
retain the handbook's legibility and authority distinctions throughout a
transition.

Use `scholium-swiftui-implementation` for Liquid Glass mechanics and
`scholium-performance-audit` for measured rendering or latency claims. This
reference does not decide either.

## Reduced-motion and non-motion meaning

Verify that provenance, focus, selection, completion, error, conflict, save,
review, Dialogue, Critique, and recovery remain understandable when decorative
or spatial motion is reduced. Apply the evidence requirements in
`accessibility-audit.md` and the routed `apple-hig` guidance.

## Report

For each issue or approved decision, state:

1. researcher task and object;
2. controlling handbook decision;
3. routed Apple and SDK sources;
4. observed behavior across entry, exit, interruption, cancellation, and recovery;
5. non-motion and alternate-input path;
6. build, fixture, device, and settings exercised; and
7. remaining uncertainty.
