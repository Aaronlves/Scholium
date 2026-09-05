# SwiftUI and native implementation loop

Use this only in Interface Implementation mode. It supplies the fast feedback
loop between live ownership, compiler evidence, a test-owned QA surface, and the
final interaction proof. Resolve current APIs and build commands from the
selected SDK, toolchain, repository, and Xcode workflow capability.
When a native container, window, or scene boundary may own the result, load
`native-window-boundary-debugging.md`; that reference owns the hierarchy,
bridge, lifecycle, and probe diagnosis rather than duplicating it here.

## Classify the failing owner

Locate the narrowest layer that owns the requirement:

- application or document state and operations;
- scene, window, commands, restoration, or navigation;
- native container, responder, scrolling, focus, geometry, or reuse;
- SwiftUI presentation, local interaction state, environment, or layout; or
- AppKit/WebKit coordination and translation.

Trace construction and the complete mutation path before editing. If a parent
container, lifecycle callback, coordinator, or domain owner controls the result,
correct that owner; if the suspected owner is a native boundary, hand the
diagnosis to the native-boundary reference before editing.

## Run one implementation loop

1. State the observable result and the single owner allowed to change it.
2. Trace identity, lifetime, mutation authority, cancellation, failure,
   recovery, focus, and teardown across every crossed framework boundary.
3. Reuse the live native or Scholium owner selected under `AGENTS.md`; define a
   thin typed translation only for a concrete remaining gap.
4. Make one compiler-valid change at the owning boundary and run the smallest
   deterministic test capable of rejecting it.
5. Use a Preview or synthetic native probe only for pure presentation or
   mechanism uncertainty. Treat it as mechanism evidence, not proof of live
   construction, state, focus, accessibility, or window behavior.
6. Build and launch one isolated QA surface when the claim depends on scene or
   window construction, responder routing, AppKit/WebKit, focus, multiwindow,
   restoration, input services, or realistic content.
7. Reproduce a failure once, inspect retained diagnostics or logs, correct the
   owner, and rebuild the same QA surface. Do not rerun an unchanged failing
   journey without new evidence.

## Route distinct evidence

- Route actor isolation, task lifetime, and `Sendable` mechanics to Swift
  concurrency only when that boundary changes.
- Route measured invalidation, rendering, CPU, or memory work to performance.
- Route CodeMirror, WebKit messages, source reconciliation, or editor identity
  to editor integration.
- Route deterministic interaction journeys and irreducible human judgment to UI
  verification.

Keep application state out of reusable views, keep coordinators free of
competing truth, and preserve source, selection, focus, Undo, composition,
conflict, cancellation, recovery, and independent-window state as applicable.
