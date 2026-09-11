# Architecture: Design System and Boundary Enforcement

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Shared
presentation implementation and executable boundary enforcement.

## Design-system implementation

[Design](../../Design.md) owns global intent and identity; §18 owns feature
presentation and state wording; §20 owns accessibility. This chapter maps shared
presentation responsibilities to code. It does not require a wrapper around a
standard system control or copy a feature's layout recipe.

| Responsibility | Current implementation owner |
| --- | --- |
| Paper input and adapted document colors; system Accent role | `ScholiumColorVariables`, `ScholiumColorResolver`, `ScholiumColorRole` and `ScholiumNativeColorRole` in `Scholium/UI/Foundation/ScholiumDesignSystem.swift`. |
| Native semantic colors | `ScholiumNativeColorRole`; AppKit/SwiftUI owns actual control rendering. |
| Native-to-document style transport | `ScholiumWebDesignTokens`; generated CSS consumes resolved values, not another palette or settings store. |
| Shared custom geometry | `ScholiumGrid`, `ScholiumMetrics`, `ScholiumShape`, surface/boundary/elevation roles; exact defaults remain in code. |
| App-owned typography | `ScholiumTypography` in `Scholium/Styling`; standard controls retain system type. |
| Chat message typography and ink | `ScholiumChatAppearance` in `ScholiumDesignSystem`; user and Agent bodies share adaptive system type and primary text, while authorship layout remains with Chat. |
| Document typography | `DocumentAppearanceSettings` and the rendering pipeline in [Documents and Editor](06-documents-and-editor.md#shared-document-rendering). |
| Shared symbols | `ScholiumSystemSymbol`; `ScholiumWebSymbolAssets` transports those symbols into WebKit. |
| Purpose-specific custom motion | `ScholiumMotion`; native controls retain their system lifecycle. |
| Page/pane state presentation | `ScholiumContentStateView`; compact Apparatus, field validation and recovery use their own bounded presentations. |

Shared values need repeated semantic or adaptation responsibility. Equal numbers
alone do not create a common owner. Native geometry stays with the platform;
local values remain with their feature. No JSON palette, geometry mirror or
second appearance configuration is authoritative.

The current native command adapters are `scholiumButtonStyle` and
`scholiumMenuStyle` in `ScholiumButtons`. They forward activation and roles to
native controls while applying shared command tint. `scholiumIconControl` owns a
bounded native glass icon recipe. These are existing mechanisms, not a mandate
to apply tint or glass throughout the app. Remaining custom feedback paths and
new target conformance are tracked in [Open Work](../Status/03-open-work.md).

Custom link-equivalent cursors use `scholiumActivationPointer` and
`ScholiumPointingHandButton` where the host does not already own the cursor.
Standard native controls and list rows do not consume these adapters. Document
CSS provides the corresponding link behavior in its renderer.

## Component boundaries

Reusable presentation leaves receive values and typed actions. They own no
Document, workflow, permission, navigation or operation lifecycle. A shared
component is justified by a repeated task, one presentation responsibility and
an adaptation contract; feature-local views need no catalog promotion.

Concrete feature ownership is recorded only in its chapter:

- [Runtime and Ownership](01-runtime-and-ownership.md#document-tabs-and-native-shell):
  native split, tabs, toolbar validation and window teardown.
- [Source Layout and Presentation](03-source-layout-and-presentation.md#presentation):
  window routes, Search, Inspector, Sidebar headers and notifications.
- [Settings integrations](04-research-guidance.md#settings-authority):
  Settings composition and native preference-window geometry.
- [Documents and Editor](06-documents-and-editor.md#editor-boundary-contract):
  retained editor, native previews, completion, Find and cross-runtime input.
- [Agent Collaboration](02-agent-collaboration.md#native-chat-client):
  Chat runtime, conversation state and receipt projections.

Native container adapters are bounded infrastructure: they own native attachment
and teardown, delegate/target lifetime and geometry, translating typed intents
without acquiring a competing domain state. A presentation reuse decision never
moves a feature's authoritative state into a style or component.

The selected Xcode also bundles `AppKit-Implementing-Liquid-Glass-Design.md`
under `IDEIntelligenceChat.framework/Resources/AdditionalDocumentation`.
It is an implementation reference, not a product design owner; sample custom
controls do not override Design's native presentation boundary.

## Boundary enforcement

Contracts, Application and App suites exercise their own module, runtime,
document and presentation responsibilities. Design checks cover semantic input
ownership, native/WebKit transport, contrast and actual shared consumers; they
must not freeze local implementation defaults or require obsolete custom skins.
`Tools/Scripts/verify.sh` also checks package dependencies, imports, I/O and
public symbols so delivery targets cannot acquire Core authority.

Debug presentation proofs consume production components and values; they are
not a second design system. [Verification Evidence](../Status/04-verification.md)
owns dated outcomes. A structural check or compiled preview does not establish
runtime interaction or human acceptance.
