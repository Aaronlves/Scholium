---
name: scholium-swiftui-implementation
description: Implement, refactor, review, or debug Scholium's SwiftUI macOS application layer. Use for scenes, windows, Settings, Commands, focused routing, state and Observation ownership, bindings, view identity and lifecycle, navigation, inspectors, layout, presentations, SwiftUI-AppKit mounting, previews, current-SDK adoption, Liquid Glass implementation, and accessibility mechanics. Do not use as the sole owner for product or HIG decisions, editor protocol mechanics, concurrency, measured performance, UI automation, vault writes, or backend and CLI work.
---

# Scholium SwiftUI Implementation

Build the native application layer from the live product contract and the selected Apple toolchain. Prefer current Apple guidance and targeted lookup over remembered APIs or a copied SwiftUI encyclopedia.

## Bind the checkout and authorities

1. Locate one repository root containing `AGENTS.md`, `Package.swift`, `Docs/PRODUCT_GUIDE.md`, `Docs/DESIGN_HANDBOOK.md`, `ScholiumCore/`, and `Scholium/`. Resolve every path from that repository root.
2. Read `AGENTS.md`, the affected Product Guide workflow, the complete Design Handbook, Section 10's exact interface contract, `Docs/IMPLEMENTATION_STATUS.md`, and the reachable source and tests.
3. Inspect `git status`. Preserve unrelated and uncommitted work.
4. Use `scholium-apple-design` to decide what the interface should communicate and whether a surface should use Liquid Glass. This skill owns how to implement the approved decision in SwiftUI.

## Establish the live platform before choosing an API

Record the selected Xcode build, Swift compiler, SDK, Swift language mode, and `Package.swift` deployment target separately. Recheck them; a beta OS does not imply a matching compiler or SDK.

```bash
developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
DEVELOPER_DIR="$developer_dir" xcodebuild -version
DEVELOPER_DIR="$developer_dir" xcrun swift --version
DEVELOPER_DIR="$developer_dir" xcodebuild -showsdks
```

The resolver honors an explicit valid `DEVELOPER_DIR` and never changes the machine-wide selection. Use its result consistently for inspection, export, builds, and tests.

Scholium's current product baseline is macOS 26 or later so the macOS 26 Liquid Glass families are first-class. Guidance for a newer SDK remains a watchlist until the selected compiler and SDK can build it. Verify availability for each symbol; never infer it from a tutorial date or OS version name.

## Acquire current Apple guidance on demand

Read [references/official-swiftui-sources.md](references/official-swiftui-sources.md) before making a current-API claim. Prefer Apple-authored skills exported from the selected Xcode instead of vendoring them into this plugin:

```bash
skill_tmp="$(mktemp -d /tmp/scholium-xcode-skills.XXXXXX)"
DEVELOPER_DIR="$developer_dir" \
  xcrun agent skills export --output-dir "$skill_tmp"
```

If export succeeds:

1. Read the exported `swiftui-specialist/SKILL.md` completely.
2. Read only the specialist references routed by the task.
3. Read the matching `swiftui-whats-new-*` skill for an SDK migration, explicit adoption request, or availability evaluation.
4. Treat the exported source as authoritative for its Xcode build, not as permission to implement a symbol absent from the selected compiler or SDK.

If export is unavailable, use the official pages in the source map and inspect exact API documentation. Community skills are secondary comparison material only; see [references/external-swiftui-skills.md](references/external-swiftui-skills.md). Do not copy or install one wholesale merely because a marketplace labels it current.

## Classify ownership before editing a view

Read [references/scholium-state-and-scene-contract.md](references/scholium-state-and-scene-contract.md), then classify each mutable value as:

- application service or registered-vault state;
- shared Triptych or vault state;
- per-window session state;
- per-document source and lifecycle state; or
- ephemeral view state.

Keep one owner and explicit projections. A property wrapper does not decide the lifetime. Trace construction, every writer, focused-command routing, restoration, and cleanup before changing ownership.

Do not perform a wholesale `ObservableObject` to Observation migration. Existing Combine models are valid when their publisher and lifetime contracts are deliberate. Use Observation for new or bounded models when it narrows invalidation and makes ownership clearer, then migrate existing models only with focused evidence and tests.

## Run a focused SwiftUI review

Before a material view change or code review, run only the applicable portions
of [references/swiftui-macos-implementation-checklist.md](references/swiftui-macos-implementation-checklist.md):

- Check deprecated or replacement APIs against the selected macOS SDK and compiler. Do not apply iOS-only guidance or replace a required AppKit/WebKit bridge merely because a newer SwiftUI API exists.
- Keep view bodies declarative, view initializers cheap, actions and business logic testable, and extraction proportional to identity, invalidation, lifecycle, or readability. Do not split files mechanically.
- Check one owner per mutable value, narrow inputs, stable semantic identity, and bindings that do not hide side effects inside `body`.
- Check navigation and presentation identity, cancellation, focus, and exact Design Handbook action labels.
- Route product meaning, HIG, accessibility, and visual decisions to `scholium-apple-design`; route measured invalidation, rendering, or resource work to `scholium-performance-audit`.
- Report reachable problems with file, line, consequence, and focused verification. Treat pattern matches as review prompts, not defects by themselves.

## Implement the application layer

### Structure, identity, and data flow

- Keep `body` a declarative projection. Move parsing, filtering, sorting, I/O, and other repeatable work into models or derived values.
- Give `ForEach`, `List`, `Table`, tabs, windows, and document surfaces stable semantic identity. Never use transient UUIDs, offsets, or mutable content as identity without proving the lifetime.
- Pass the narrowest stable inputs a child needs. Avoid broad environment reads when a leaf requires one value.
- Keep side effects in explicit actions, lifecycle modifiers, or model methods. Use `.task(id:)` only when identity-driven cancellation and restart are intended.
- Preserve source buffers, selection, focus, undo, scroll position, and conflict state across view updates and mode changes.

### Scenes, windows, commands, and presentation

- Keep app services shared deliberately and window interaction state independent.
- Route menu and keyboard commands through `FocusedValue`, `FocusedSceneValue`, or the responder chain to the focused window or document; never mutate an unrelated global selection.
- Use `SceneStorage` for lightweight restorable presentation state, not authoritative research data.
- Keep navigation history, in-window document tabs, native window tabs, and Read/Live Preview/Source modes distinct.
- Give sheets, alerts, popovers, inspectors, and context menus stable item identity, explicit cancellation, and the exact actions defined by the Design Handbook.

### Layout and framework boundaries

- Prefer native `NavigationSplitView`, inspector, toolbar, table, and window behavior when they meet the tested macOS task.
- Preserve the current `HSplitView` inspector workaround until the original WebKit constraint failure is remeasured on the selected toolchain and the replacement passes resize, focus, restoration, and editor tests.
- Treat `NSViewRepresentable` and `NSViewControllerRepresentable` as lifecycle adapters: construct once for stable identity, update idempotently, coordinate delegates explicitly, dismantle resources, and avoid feedback loops.
- Pair with `scholium-markdown-editor-integration` for CodeMirror/WKWebView buffer, range, selection, undo, composition, CSP, or navigation-policy mechanics.

## Implement an approved material decision

Use `scholium-apple-design`, the Design Handbook, and routed `apple-hig`
guidance to decide whether and where Liquid Glass belongs. This skill owns only
the SwiftUI/AppKit mechanics of that approved decision:

1. Verify every symbol against the resolved compiler and SDK.
2. Prefer the verified standard component or system hierarchy named by the
   design decision before adding custom material code.
3. Remove only implementation details that demonstrably conflict with that
   approved hierarchy; do not infer a redesign from the availability of a new
   API.
4. Give custom material stable identity, bounded grouping, explicit framework
   ownership, and a focused rendering test.
5. Run the appearance, accessibility, resizing, focus, scrolling, inactive-
   window, and performance checks required by the Design Handbook and routed
   Apple guidance.

Do not add compatibility branches for pre-macOS 26. Never infer API
availability from the host OS or a remembered toolchain snapshot.

## Route narrow concerns

- Product meaning, HIG interpretation, visual hierarchy, and the decision to use glass: `scholium-apple-design`.
- Actor isolation, `Sendable`, task lifetime, and synchronization: `swift-concurrency`.
- Non-SwiftUI language mechanics and API naming: `swift-language` and `swift-api-design-guidelines`.
- Measured invalidation, hitches, launch, or rendering work: `scholium-performance-audit`.
- Deterministic GUI journeys and accessibility identifiers: `scholium-ui-automation`.
- Trust-sensitive writes, private data, CSS, or WebKit messages: `scholium-trust-boundary-audit` plus the narrow owner.
- Shared repositories, watchers, indexes, `WorkspaceCommit`, cross-window save acknowledgement, or external-file races: `scholium-vault-file-coordination`.

## Verify and report

Use [references/swiftui-macos-implementation-checklist.md](references/swiftui-macos-implementation-checklist.md). During iteration, compile the affected target and exercise deterministic previews. For a material GUI change, use the isolated QA app and disposable fixtures:

```bash
./Tools/Scripts/build-qa-app.sh
./Tools/Scripts/run-ui-tests.sh
```

Finish repository implementation through `scholium-development` and its verification command. Report the selected toolchain and SDK, Apple sources consulted, state owner, affected lifecycle states, Liquid Glass role, exact build and fixture exercised, accessibility/adaptation coverage, and remaining uncertainty. Do not claim that a preview or clean compile proves a complete user journey.
