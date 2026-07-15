---
name: scholium-apple-design
description: Apply Scholium's PRODUCT_GUIDE.md and DESIGN_HANDBOOK.md to macOS interface decisions while using apple-hig as the sole authority for Apple Human Interface Guidelines. Use for Scholium windows, navigation, document modes, menus, toolbars, search, properties, Review, Dialogue, Critique, checkpoints, conflicts, accessibility, settings, fluid interaction, motion, materials, typography, and visual review. Pair with implementation, performance, automation, trust, or editor skills when those mechanics are in scope.
---

# Scholium Apple Design

Apply Scholium's product-specific design rules to the native macOS interface.
Keep the research document primary and preserve visible research authority,
uncertainty, conflict, recovery, and agent authorship.

## Locate the checkout

Do not infer the checkout from this installed skill. Bind one repository root containing `AGENTS.md`, `Package.swift`, `Docs/PRODUCT_GUIDE.md`, `Docs/DESIGN_HANDBOOK.md`, `ScholiumCore/`, and `Scholium/`. If no unique root is in scope, stop and request the checkout. Resolve source paths from the repository root.

## Route and load guidance

1. Read `Docs/PRODUCT_GUIDE.md` for the affected target feature and workflow.
2. Read `Docs/DESIGN_HANDBOOK.md` completely before material interface work.
3. Read Section 10, **Canonical interface state and action contract**, before changing information architecture or user-visible state and actions. It is the sole contract for target UI state meanings, Dialogue/Critique/checkpoint actions, conflict actions, and exact labels.
4. Use `apple-hig` for every HIG claim. Follow its routing protocol for macOS and the affected foundations, patterns, and components. Do not maintain a second HIG summary or override its guidance inside this skill.
5. For an implementation-facing API claim, inspect the exact symbol in the selected Xcode installation's Developer Documentation and verify it against the selected SDK and compiler. Mark unavailable inspection or unverified availability explicitly.
6. Read [references/accessibility-audit.md](references/accessibility-audit.md) for accessibility work or changes affecting focus, keyboard behavior, text, color, motion, custom controls, AppKit/TextKit, reachable WebKit, or Canvas interaction.
7. Read [references/fluid-interaction.md](references/fluid-interaction.md) for Scholium-specific questions involving gesture-driven interaction, interruptible transitions, spatial continuity, or motion-sensitive research workflows. Treat it as a task checklist, not as HIG authority, a timing catalog, or a product contract.
8. Inspect the complete reachable task and adjacent states. Use only the isolated `com.kbmanager.qa` Debug app and disposable fixtures for automated GUI evidence; never expose private research content.
9. Pair with:
   - `scholium-development` for implementation and final build verification;
   - `scholium-swiftui-implementation` for scenes, state ownership, navigation, layout, presentation, SwiftUI-AppKit mounting, and Liquid Glass mechanics;
   - `scholium-markdown-editor-integration` for source buffers, TextKit ranges, projection, undo, focus, or reachable WebKit;
   - `scholium-performance-audit` only when a measured latency or resource goal is in scope;
   - `scholium-ui-automation` for isolated QA-app journeys, launch-state isolation, and release-artifact smoke tests only when release verification is explicitly in scope;
   - `scholium-trust-boundary-audit` for writes, proposals, conflicts, restore, permissions, or private-data handling.

## Authority boundary

- `apple-hig` owns Apple HIG rules, measurements, patterns, components, and platform distinctions.
- Xcode Developer Documentation, the selected SDK, and the compiler own API behavior and availability.
- `PRODUCT_GUIDE.md` owns target product behavior and feature boundaries.
- `DESIGN_HANDBOOK.md` owns Scholium-specific interface structure, terminology, exact user-visible states and actions, and stable design decisions.
- `references/fluid-interaction.md` supplies Scholium-specific review questions for motion-sensitive workflows; it does not add product behavior, replace native macOS patterns, or override `apple-hig`.
- `IMPLEMENTATION_STATUS.md`, source, and tests establish current reachability; they do not silently override target design.

Do not attribute Scholium's Triptych, research governance, evidence hierarchy,
Dialogue, Critique, or recovery model to Apple. When Apple guidance requires a
Scholium interpretation, identify both layers. Treat current-code divergence as
implementation debt, and mark future or unverified behavior explicitly. If a
stable Scholium decision conflicts with `apple-hig`, report the conflict and
require an explicit documented exception or handbook change; do not silently
weaken or reinterpret the HIG rule.

## Verify and report

1. Exercise the complete task, including applicable empty, loading, failure, conflict, and recovery states.
2. Verify window resizing, appearance and accessibility settings, menu/toolbar/keyboard/pointer/focus parity, and editor undo versus version restore.
3. Use previews for deterministic states and `scholium-ui-automation` for isolated QA journeys. Treat exploratory inspection as supplementary evidence.
4. Run the Design Handbook checklist and record exceptions or uncertainty.
5. Report the researcher task, handbook decision IDs, routed `apple-hig` topics, verified Xcode symbols when applicable, Scholium interpretation, exercised build and fixture, and remaining uncertainty.

For accessibility findings, use the priorities and required evidence in `references/accessibility-audit.md`.
