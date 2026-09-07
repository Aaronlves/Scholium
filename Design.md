# Scholium Design

Part of the canonical set rooted at
[SCHOLIUM_SPEC.md](Docs/SCHOLIUM_SPEC.md). This document owns §19: the stable
global design philosophy and visual identity. Feature behavior and composition
belong to §§18.1–18.7; accessibility and adaptation requirements belong to §20.

## 19. Scholarly Editorialism

Scholium is a native Mac research environment centered on the document.
**Scholarly Editorialism** means a quiet reading and writing space, clear
editorial hierarchy, and tools that remain subordinate to the researcher's work.
Only the configured main workspace adds Scholium background color and Accent.
Its controls, navigation, typography outside document content, geometry,
feedback, and auxiliary windows follow macOS.

Change this document only when the global philosophy or identity changes.
A new feature, local layout adjustment, SDK update, or implementation correction
normally changes its owning chapter or code. Do not accumulate component
catalogs, numeric recipes, feature exceptions, or current acceptance here.
[AGENTS.md](AGENTS.md#design-document-change-boundary) governs Agent edits and
the document validator enforces its bounded structure.

### 19.1 Content and native Liquid Glass

The main workspace is the configured window's Sidebar (Library or Chat),
Document and Apparatus content. It excludes separate windows and transient
menus, popovers, sheets, dialogs and previews, even when opened from that window.

The interface has a content layer and a navigation/operation layer. The main
Document provides a calm, opaque Paper background for sustained reading;
adjacent research content shares that background identity. The background may
continue beneath native chrome so the workspace feels continuous. Text remains
within the native safe area.

Liquid Glass belongs to the system's navigation and floating controls. Let
native containers establish their material, grouping, scroll-edge separation,
geometry and adaptation. Background color can contribute through the material;
do not paint a second brand surface over it or turn research prose into glass
cards. Native does not require applying a glass style to every button.

All auxiliary presentation uses system backgrounds, colors, control accent,
typography and materials, without inheriting the main workspace's Paper or Accent.
This includes onboarding, Settings, connection management, advanced search,
notifications, file comparison, recovery and transient research previews.
Containing source text or being anchored to the main window creates no exception.

No feature recreates blur, refraction, shadows, highlights, focus rings,
selection plates or control animation. Embedded document rendering does not
simulate Liquid Glass. When a custom host is necessary at a framework boundary,
it uses the system material and retains native input and accessibility.

### 19.2 Background and Accent

The main workspace has two configurable identity inputs:

- **Paper** `#FEF8ED`: the light document-background anchor, adapted for appearance.
- **Accent** `#A94C22`: restrained main-workspace emphasis through supported
  native tinting and document links.

These colors express identity; they do not replace system label, separator,
control, selection, focus, warning or destructive semantics. Ordinary actions
retain native prominence. Do not tint every clickable item or impose a separate
neutral-selection skin. System accessibility and appearance preferences take
precedence over an exact color match.

The main Document renderer shares its host's background and Accent meanings. Authored formatting, including highlights, remains document presentation;
it is not another application theme or a workflow-state palette.

### 19.3 Typography, layout and motion

Use system typography and system metrics for the interface. Document Appearance
owns the researcher's reading and source typography under §18.4; font selection
does not theme app chrome or alter source. Hierarchy comes from content order,
type, alignment and spacing before containers or decoration.

The Document receives the usable space left by navigation and research context.
Native containers govern resizing, collapse and overflow; feature chapters
specify which content and routes remain available. Avoid fixed geometry that
prevents native adaptation. Exact spacing, font sizes, opacity, radii and timing
remain implementation defaults unless an owning requirement needs a threshold.

Native controls and containers own interface motion. Do not add a separate
feedback animation system. Motion never delays input or celebrates a research
judgment; §20 owns Reduce Motion and other adaptation requirements.

### 19.4 Symbols and identity artwork

Use familiar system symbols for standard actions, with native rendering.
Custom research objects may need a distinct symbol, but do not create a second
icon family for familiar Mac operations.

The approved application icon is the parchment-and-ink cuffed hand pointing
right toward a marginal rule and manuscript strokes. Its composition is stable
identity, not a control, state glyph or Appearance setting. Replacing it requires
explicit researcher approval. Illustration colors belong to the artwork itself;
they never authorize a branded window background or control palette.

### 19.5 Interface writing

Use the shortest accurate label that predicts the immediate result. Prefer a
direct verb or established research term. Supporting copy explains a necessary
boundary, unfamiliar consequence or actionable repair. Do not repeat visible
copy in Help; accessibility hints add only missing context.

State only what Scholium can verify. Quietness never removes necessary source
attribution, permission, uncertainty, errors or recovery. §18.6 owns state
vocabulary and §18.7 owns translations.

### 19.6 Apple references

Apple's official references inform platform presentation; the Scholium
specification owns research meaning and the choices above. Consult the current
HIG and selected SDK when implementing, rather than freezing their API details
in this document.

- [Materials — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/materials):
  content hierarchy and system materials.
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass):
  standard components, content visibility and restrained customization.
- [Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/):
  native Mac toolbar/sidebar composition, safe areas and floating controls.
