# Native container and window boundary diagnosis

Use this when the defect may belong above an ordinary view: native containers,
source lists, outlines, scrolling, toolbars, titlebars, tabs, window geometry,
responder routing, restoration, or scene lifecycle. The general implementation
loop and test cadence remain in `swiftui-implementation-loop.md`; this
reference owns only the native-boundary diagnosis and probe contract.

## Bind the owner

Classify the failing invariant as local view layout, container layout, window
structure, or scene lifecycle. Inspect the live native hierarchy and
construction path before adding modifiers or delays. Stop tuning a child when
the container, window, or later lifecycle callback owns the result.

Prefer the documented SwiftUI owner when it can express the requirement. Use a
narrow AppKit adapter only when the behavior is natively owned, SwiftUI does
not expose the required control, and a public AppKit contract can preserve
standard macOS semantics. Do not paint an imitation of a native role.

A SwiftUI/AppKit bridge is not itself a defect; parallel ownership is. Before
implementation, write one short contract naming the model owner, the native
container owner, the declarative-content owner, and the coordinator's
translation duty. Assign geometry, identity and reuse, interaction state, and
lifecycle once. Label each boundary crossing as an event or state projection
and keep its reconciliation idempotent. The coordinator may translate stable
identities and explicit intents, but it must not create another truth or a
feedback loop.

## Build in causal order

Prove the native mechanics first with the smallest synthetic hierarchy and one
falsifiable interaction. Then connect the real projection through stable
identity and idempotent, difference-only synchronization, including observer
and tracking teardown. Add Scholium row content and visual treatment only after
container mechanics, focus, and accessibility remain intact.

If a proposed correction depends on repeated reloads, geometry polling,
delayed callbacks, overlay hit regions, duplicated transient state, or a
simulated native control, stop and reopen the ownership contract. Such a
mechanism may be justified, but only after the native owner has been shown
unable to carry the invariant.

## Resolve remaining uncertainty

When documentation and construction do not distinguish plausible mechanisms,
build the smallest disposable native probe with synthetic content and one
falsifiable action. A passing probe proves only the mechanism, not Scholium's
design, state, accessibility, or release behavior.

For lifecycle defects, write the observed and intended ordering from identity
creation through host attachment, restoration, presentation, focus changes,
later layout, and teardown. Name the owner allowed to mutate the affected value
at each stage. Prefer the earliest stable owner over repeated delayed callbacks.

## Boundary-specific proof

State the invariant independently of appearance, including identity, region
ownership, focus, restoration, commands, accessibility, and independent-window
state as applicable. A probe proves only native mechanism; it does not prove
Scholium design, state, accessibility, or release behavior. Return the real
owner, the ownership contract, the lifecycle ordering, the smallest correction,
and the remaining uncertainty to the implementation loop for compiler, focused
test, and QA evidence.
