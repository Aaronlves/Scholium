# Current Apple SwiftUI source map

Refresh directly relevant sources before relying on a latest-version claim.

## Source order

1. The selected Xcode's exported Apple skills for best practices tied to that toolchain.
2. Exact Apple SwiftUI or AppKit API documentation for signatures and availability.
3. Current Apple tutorials and WWDC sessions for design process, framework direction, and migration context.
4. Scholium's Product Guide and Design Handbook for project-specific meaning.

Resolve and record the live Xcode, Swift compiler, and SDK independently. Do not preserve a version snapshot in this reference.

## Export Apple-authored skills

```bash
tmp="$(mktemp -d /tmp/scholium-xcode-skills.XXXXXX)"
developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
DEVELOPER_DIR="$developer_dir" \
  xcrun agent skills export --output-dir "$tmp"
```

If the user authorizes a particular Xcode bundle, set `developer_dir` to that bundle's `Contents/Developer` directory first. Read `swiftui-specialist/SKILL.md` and only its routed references. Read a `swiftui-whats-new-*` bundle for migration, explicit adoption, or availability evaluation, but do not implement an API absent from the selected SDK. Do not vendor the exported files: they change with Xcode and carry no standalone redistribution license.

## Curriculum and framework

| Official source | Use it for |
| --- | --- |
| [Develop in Swift](https://developer.apple.com/tutorials/develop-in-swift/) | Current curriculum index and orientation. |
| [App Design](https://developer.apple.com/tutorials/develop-in-swift/welcome-to-app-design) | User needs, problem framing, feature priority, journeys, prototypes, testing, and iteration. |
| [App Development](https://developer.apple.com/tutorials/develop-in-swift/welcome-to-app-development) | Complete data-to-view flows, navigation, debugging, appearance, accessibility, localization, and current system design. Translate iOS examples to the Mac task. |
| [Hello SwiftUI](https://developer.apple.com/tutorials/develop-in-swift/hello-swiftui) | Declarative composition, modifiers, previews, and compiler-guided iteration. |
| [Welcome to SwiftUI](https://developer.apple.com/tutorials/develop-in-swift/welcome-to-swiftui) | Custom views, properties, layout, state, and dynamic interfaces. |
| [Data Modeling](https://developer.apple.com/tutorials/develop-in-swift/welcome-to-data-modeling) | Explicit domain types, relationships, business logic, tests, persistence, and previews. |
| [SwiftUI documentation](https://developer.apple.com/documentation/swiftui) | Canonical framework entry point and exact API pages. |
| [SwiftUI app organization](https://developer.apple.com/documentation/swiftui/app-organization) | App, scenes, windows, documents, commands, navigation, and platform tailoring. |
| [Managing model data](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app) | State, bindings, Observation, environment, and model/view separation. |
| [SwiftUI performance analysis](https://developer.apple.com/documentation/swiftui/performance-analysis) | Instruments, update causes, hangs, and hitches. Pair with Scholium's measurement skill. |

The tutorials are teaching material, not a macOS information-architecture specification. Preserve Scholium's native Mac workflows and hybrid SwiftUI/AppKit architecture.

## Liquid Glass and Mac integration

| Official source | Use it for |
| --- | --- |
| [Liquid Glass overview](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass) | System design, hierarchy, and cross-framework overview. |
| [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) | Standard components first, content scrolling beneath controls, hierarchy, and migration. |
| [Materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials) | Functional-layer placement, legibility, contrast, and restraint. |
| [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) | `glassEffect`, containers, identity, transitions, shapes, and custom controls. |
| [Build an app with Liquid Glass](https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass) | End-to-end sample; extract principles rather than copying its app structure. |
| [Build a SwiftUI app with the new design (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/323/) | Native adoption and migration walkthrough. |
| [Meet Liquid Glass (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/219/) | Design rationale and layer model. |
| [Use SwiftUI with AppKit and UIKit (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/272/) | Incremental hybrid architecture and framework interoperability. |

SwiftUI and AppKit custom Liquid Glass APIs begin on macOS 26. Scholium targets macOS 26 or later, so they may be primary APIs after exact symbol verification.

## Newer-toolchain watchlist

- [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui) is the canonical dated change index.
- [What's new in SwiftUI (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/269/) covers Xcode 27-era changes.
- [TN3211](https://developer.apple.com/documentation/technotes/tn3211-resolving-swiftui-source-incompatibilities-for-state-and-contentbuilder) governs Xcode 27 `State` and `ContentBuilder` migration issues.
- [Extending and customizing agents in Xcode](https://developer.apple.com/documentation/xcode/extending-and-customizing-agents) documents Apple skill export.

Do not use Xcode 27-only `State` macro behavior, document APIs, generalized reorder/swipe containers, toolbar overflow controls, or other release-specific APIs until the selected compiler and SDK expose them. Check every related symbol independently because availability can differ within one feature family.
