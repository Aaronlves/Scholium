# Scholium state and scene contract

This map describes ownership questions, not a mandate to rewrite the current architecture. Reinspect live construction and call sites before every material state change.

## Ownership map

| Lifetime | Typical Scholium owner | Appropriate contents | Must not own |
| --- | --- | --- | --- |
| Application process | app-level service container | vault identity registry, shared repositories, watchers, per-vault indexes, service configuration | focused note, sheet presentation, one window's tabs |
| Triptych or vault | shared workspace service/store | catalog, derived graph/search generations, diagnostics, registered roots | editor selection, per-window navigation, uncommitted source buffer |
| Window scene | one `AppState` / `WindowSession` created by `WindowGroup` | selection, tabs, navigation history, search/filter presentation, inspector mode/width, sheet state, focused routing | another window's selection or global authoritative source |
| Document | document/editor session keyed by stable vault and note identity | exact source buffer, committed fingerprint, edit/save/conflict state, selection, undo bridge, mode and scroll restoration | app-wide services or replaceable derived truth |
| View-local | `@State`, focus, animation, disclosure, hover | short-lived presentation state owned by one stable view identity | repository data, durable review state, cross-window coordination |

Persistence does not change authority. `SceneStorage` may restore a selected presentation value, but it never becomes the source of truth for a note, review, vault, or index.

## Current architecture to preserve until deliberately changed

- `ScholiumApp.swift` creates shared workspace services and a separate per-window `AppState` through `WindowGroup`.
- Focused commands route through focused values rather than an arbitrary global selection.
- Much of the current application model uses Combine and `@EnvironmentObject`. This is a live contract, not automatically obsolete because Observation exists.
- `ContentView` uses `NavigationSplitView` plus a deliberate `HSplitView` trailing-inspector workaround after a beta macOS/WebKit constraint loop. Replace it only with a measured reproduction and complete resize/focus/restoration verification.
- CodeMirror and WKWebView are active `NSViewRepresentable` boundaries. Their stable identity, delegate lifecycle, bridge ordering, focus, and buffer reconciliation belong to the editor integration contract.

## Choosing SwiftUI state tools

- Use immutable stored inputs for values a view receives and does not own.
- Use `@State` for value or Observation-backed state whose lifetime is the stable identity of that view.
- Use `Binding` or `@Bindable` for a narrow mutation capability passed from the owner.
- Use environment values for genuinely ambient policy or services. Avoid high-frequency or unstable values that invalidate broad subtrees.
- Use `@Observable` for a new bounded model when per-property tracking and direct ownership improve the design. Add `@MainActor` when it owns UI state.
- Keep `ObservableObject`, `@StateObject`, `@ObservedObject`, and `@EnvironmentObject` when existing publisher semantics and shared ownership remain intentional.
- Do not store the same mutable fact in both Observation and Combine models. Adapt at one explicit boundary during incremental migration.

## Identity and lifecycle rules

1. Identify notes with stable vault identity plus vault-relative path or the canonical live note identity—not title, row offset, or a fresh UUID.
2. Key document sessions and tabs separately from navigation visits and presentation modes.
3. Tie `.task(id:)` to the semantic input that should cancel and restart the operation. Make cancellation cooperative in the model.
4. Do not initiate work from `body`, computed view fragments, or formatter creation repeated on each update.
5. Keep one owner for a sheet/alert/popover item and clear it through the lifecycle's exact cancel or completion action.
6. Preserve uncommitted buffers when a window, inspector, or navigation column updates.
7. Dismantle observers, delegates, timers, and tasks when a representable or window session ends.

## Migration gate

Before migrating an existing model to Observation, record:

- the current owner and construction path;
- every window and document that shares it;
- every publisher or side effect consumers depend on;
- baseline SwiftUI invalidation evidence when performance is the reason;
- the migration boundary and compatibility adapter;
- focused tests for window isolation, command routing, save/conflict state, and deallocation.

No migration is justified solely by tutorial preference or fewer property-wrapper characters.
