# SwiftUI macOS implementation checklist

Use the applicable sections; do not turn a narrow view change into an app-wide refactor.

## Authority and platform

- [ ] The researcher task and affected research object are explicit.
- [ ] Product Guide, complete Design Handbook, Section 10, live source, and adjacent states were inspected.
- [ ] Xcode build, Swift version, SDK, language mode, and macOS 26 deployment target were verified separately.
- [ ] The relevant exported Apple skill/reference or exact official API page was read.
- [ ] Every implementation-facing symbol was verified against the resolved compiler and SDK rather than a version snapshot or host-OS assumption.

## State, identity, and lifecycle

- [ ] Each value has one application, workspace, window, document, or view-local owner.
- [ ] Child views receive narrow stable inputs rather than unnecessary broad models.
- [ ] Lists, rows, tabs, documents, and windows use stable semantic identity.
- [ ] Work does not start in `body`; task restart and cancellation match semantic identity.
- [ ] Sheet, alert, popover, inspector, and conflict state have exact completion and cancellation paths.
- [ ] Multiwindow changes cannot mutate another window's selection, sheet, history, or focused command target.

## Mac interaction

- [ ] Menu, toolbar, context menu, keyboard, pointer, responder, focus, and accessibility routes agree.
- [ ] Back/Forward, tabs, native window tabs, and Read/Live Preview/Source remain distinct.
- [ ] Search, Quick Open, and in-note Find keep distinct scope and focus behavior.
- [ ] Split views preserve a usable document at minimum width and restore intended visibility and dimensions.
- [ ] Long labels, mixed Chinese/Latin text, right-to-left chrome, and 200% document text do not clip or force ordinary prose to scroll horizontally.

## SwiftUI and AppKit/WebKit boundaries

- [ ] Representable construction is stable; updates are idempotent and avoid delegate/bridge feedback loops.
- [ ] Coordinators, observers, delegates, tasks, timers, and resources have an explicit teardown path.
- [ ] Selection, focus, marked text, undo, scroll position, and buffer revision survive unrelated SwiftUI updates.
- [ ] The current inspector workaround is preserved unless its original failure was remeasured and the replacement verified.
- [ ] Editor protocol work was routed through `scholium-markdown-editor-integration`.

## Liquid Glass

- [ ] The surface is a functional control or navigation layer, not research content decoration.
- [ ] Standard SwiftUI/AppKit components were tried before custom glass.
- [ ] Interfering custom backgrounds, capsules, borders, shadows, and metrics were removed deliberately.
- [ ] Custom effects are limited to important custom interactive controls and grouped through the system container when appropriate.
- [ ] Dense prose, source, diffs, diagnostics, and metadata bodies remain legible content surfaces.
- [ ] Light/dark, inactive window, Reduce Transparency, Increase Contrast, Reduce Motion, scrolling beneath controls, focus, VoiceOver, and resize behavior were exercised.

## Performance and verification

- [ ] Parsing, sorting, filtering, formatting, I/O, and graph work stay outside `body` and the main actor where safe.
- [ ] Performance claims use the performance skill and a measured before/after scenario.
- [ ] Deterministic previews cover representative ready, empty, loading, error, conflict, long-content, and accessibility states where applicable.
- [ ] Focused tests cover state/model behavior; XCUITest covers the complete interaction when material.
- [ ] The isolated QA app used disposable nonprivate fixtures.
- [ ] The report states the exact source/toolchain/build/fixture, Apple guidance consulted, result, and remaining uncertainty.
