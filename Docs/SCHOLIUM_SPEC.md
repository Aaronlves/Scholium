# Scholium Specification

- **Status:** Canonical product, interface, and release specification
- **Applies to:** Scholium for macOS and its agent-facing CLI

This is the sole entry point and closed manifest for target product,
interface, accessibility, release, and stable-decision authority. Only the
chapters listed below are normative. Structure belongs to
[IMPLEMENTATION_ARCHITECTURE.md](IMPLEMENTATION_ARCHITECTURE.md); reachability,
open work, and evidence belong to
[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md). Apple HIG and the selected
SDK own platform behavior; this set owns Scholium's research semantics and
governance.

## Set contract

The three document sets have distinct jobs:

| Set | May contain | Must not contain |
| --- | --- | --- |
| Specification | Stable target behavior, terminology, interface semantics, accessibility, release requirements, and unresolved target decisions | Current reachability, module/type descriptions, migration history, test counts, or operator instructions |
| Implementation Architecture | Current module, runtime, dependency, state-owner, persistence, and delivery structure | Alternative product rules, superseded designs, migration plans, acceptance results, or release claims |
| Implementation Status | Dated reachability, open work, verification evidence, and acceptance boundaries | New target rules, structural design authority, completed migration narratives, or decision chronology |

Operational guides may explain current tools but create no fourth authority.

## Canonical chapters

Read this manifest first, then only the chapters required by the task. A
cross-chapter change must update every owning chapter in one patch without
copying the same rule into a new summary.

| Chapter | Owns |
| --- | --- |
| [Foundation and Triptych](Specification/01-foundation-and-triptych.md) | Sections 1–4: terminology, product authority, Triptych structure, and Works organization. |
| [Notes and Lifecycle](Specification/02-notes-and-lifecycle.md) | Sections 5–7: common Note behavior, lifecycle Locations, settlement, annotation, and Discussion. |
| [Research Actions and Workflows](Specification/03-research-actions-and-workflows.md) | Sections 8–11: Actions and the Analysis, Topic, and Work workflows. |
| [Connect, Search, and Recovery](Specification/04-connect-search-and-recovery.md) | Sections 12–14: Connections, Search, Attention, checkpoints, versions, and recovery. |
| [Integrations, Onboarding, and Boundaries](Specification/05-integrations-onboarding-and-boundaries.md) | Sections 15–17: Zotero, onboarding, permanent boundaries, and deferred capabilities. |
| [Interface Shell and Library](Specification/06-interface-shell-and-library.md) | Sections 18.1–18.3: global interface principles, workspace shell, Library, and Search presentation. |
| [Document and Research Interface](Specification/07-document-and-research-interface.md) | Sections 18.4–18.7: Document modes, Research Inspector, Document-owned state meanings, and terminology. |
| [Scholium Design](../Design.md) | Section 19: Scholarly Editorialism, visual language, design Variables, component and pattern presentation, layout, icon, motion, and interface writing. |
| [Accessibility and Adaptation](Specification/09-accessibility-and-adaptation.md) | Section 20: cross-cutting accessibility and adaptation requirements. |
| [Release and Open Decisions](Specification/10-release-and-open-decisions.md) | Sections 21–22: release requirements, acceptance, and unresolved target decisions. |
| [Property Profiles and Critique](Specification/11-property-profiles-and-critique.md) | Appendices A–B: default property profiles and bundled Critique requirements. |

## Reading routes

- A Note/source/lifecycle task starts with Notes and Lifecycle, then adds the
  relevant storage, interface, or accessibility chapter only when affected.
- A Research Action task starts with Research Actions and Workflows and adds
  the exact role workflow, interface, or release chapter it changes.
- Sidebar, file-tree, Document, and editor tasks add the owning interface and
  Accessibility chapters; visual-language changes also add Scholium Design.
  Parser and implementation detail stays in Implementation Architecture.
- Release work reads Release and Open Decisions plus the current verification
  chapter rooted at [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).

Section numbers and meanings remain unique across the closed set. Git owns
replaced wording and chronology; do not retain a compatibility copy of moved
specification prose.
