# SwiftUI performance checks

Use these checks to form hypotheses, not to declare a bottleneck without runtime evidence.

## Invalidation and identity

- Find views that observe all of `AppState` or a large model but render only one derived value.
- Check whether a high-frequency property change invalidates unrelated sidebar, editor, inspector, or canvas subtrees.
- Require stable domain identifiers for notes and relationships. Treat `id: \.self`, transient indices, or regenerated UUIDs as suspicious when data can reorder.
- Prefer stable root structure and localized conditional sections over swapping unrelated top-level view trees.
- Treat `AnyView` and unnecessary type erasure as possible identity and optimization barriers.

## Work during rendering

- Flag sorting, filtering, Markdown parsing, graph traversal, relationship resolution, formatter construction, disk access, or SQLite work performed from `body` or a frequently evaluated view helper.
- Prefer system `FormatStyle` APIs when they express the output without repeatedly constructing formatters.
- Keep view initializers cheap and deterministic. Start cancellable asynchronous work with `.task(id:)` when it belongs to the view lifecycle.
- Do not use `@State` as an arbitrary cache. A derived value stored in view state needs explicit inputs and invalidation semantics.

## Structural choices

- Prefer changing modifier values over replacing a view's structure when the two branches have the same semantics and lifecycle; do not force this rule when branches differ in accessibility, focus, teardown, or state ownership.
- Avoid `AnyView` and unnecessary view-builder indirection when they obscure identity or invalidation, but do not extract every helper into a new file merely to satisfy a generic style rule.

## Collections and layout

- Precompute filtered or sorted inputs before `ForEach` when the transformation would repeat across updates.
- Use lazy containers for genuinely large scroll content, while checking that laziness does not break selection or measurement behavior.
- Look for nested geometry readers, preference chains, or canvas-wide geometry changes that trigger broad layout work.
- Check whether moving one canvas card recomputes every card and relationship line or persists on every pointer event.

## Main actor and bridges

- Keep AppKit and WebKit mutations on the main actor.
- Move only Sendable, UI-independent CPU work to an actor or `@concurrent` helper.
- Check Read-mode HTML reload signatures, CodeMirror ready/setDocument traffic, CSS/link-completion updates, UTF-16 editor deltas, any save-buffer reconciliation, and source-line JavaScript round trips for redundant work.
- Do not replace actor safety with detached tasks, unchecked sendability, or unsynchronized caches.

## Remediation order

1. Repeated main-thread parsing, indexing, or rendering work.
2. Broad observation fan-out and unstable list identity.
3. Redundant WebKit/AppKit bridge work.
4. Canvas-wide recomputation and persistence frequency.
5. Layout and animation polish.

After each change, repeat the same measurement before proceeding.
