# Scholium Specification

- **Status:** Canonical product, interface, and release specification
- **Applies to:** Scholium for macOS and its agent-facing CLI

This file is the sole entry point and closed manifest for Scholium's target
authority. The chapters listed below are normative parts of this one
specification set; a file not listed here cannot define product, interface,
action-language, Scholarly Editorialism, accessibility, release, or stable
decision requirements.

[IMPLEMENTATION_ARCHITECTURE.md](IMPLEMENTATION_ARCHITECTURE.md) describes
structure. [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md), README, live
construction, tests, and scripts establish reachability and evidence.
Implementation divergence is tracked outside the specification and never
defines an alternative target.

In this specification:

- **Target** is required behavior, whether implemented or not.
- **Reachable** means exposed by the current build, not accepted for release.
- **Verified** means directly exercised by the stated evidence.
- **Deferred** is intentionally outside the stated release boundary.
- **Unresolved** means a decision or acceptance judgment remains open.

Apple HIG and the selected SDK own platform/API behavior; this specification
owns the Triptych, scholarly semantics, evidence, and research governance.

## Set contract

The three document sets have distinct jobs:

| Set | May contain | Must not contain |
| --- | --- | --- |
| Specification | Stable target behavior, terminology, interface semantics, accessibility, release requirements, and unresolved target decisions | Current reachability, module/type descriptions, migration history, test counts, or operator instructions |
| Implementation Architecture | Current module, runtime, dependency, state-owner, persistence, and delivery structure | Alternative product rules, superseded designs, migration plans, acceptance results, or release claims |
| Implementation Status | Dated reachability, open work, verification evidence, and acceptance boundaries | New target rules, structural design authority, completed migration narratives, or decision chronology |

Operational guides may explain how to use a current tool, but they are not a
fourth authority and must route every behavioral claim back to one of these
sets or to installed command help.

Scholium uses direct agent edits. Unsupported application state fails closed
and remains unparsed and
untouched; unsupported data never authorizes behavior. Scholium never deletes
or normalizes researcher Markdown, custom YAML, or unrecognized Triptych files
merely because it does not interpret them.

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
| [Document and Research Interface](Specification/07-document-and-research-interface.md) | Sections 18.4–18.7: Document modes, Research Inspector, state meanings, and terminology. |
| [Scholarly Editorialism and Design System](Specification/08-design-system.md) | Section 19: visual language, Variables, layout, application icon, and interface writing. |
| [Accessibility and Adaptation](Specification/09-accessibility-and-adaptation.md) | Section 20: cross-cutting accessibility and adaptation requirements. |
| [Release and Open Decisions](Specification/10-release-and-open-decisions.md) | Sections 21–22: release requirements, acceptance, and unresolved target decisions. |
| [Property Profiles and Critique](Specification/11-property-profiles-and-critique.md) | Appendices A–B: default property profiles and bundled Critique requirements. |

## Reading routes

- A Note/source/lifecycle task starts with Notes and Lifecycle, then adds the
  relevant storage, interface, or accessibility chapter only when affected.
- A Research Action task starts with Research Actions and Workflows and adds
  the exact role workflow, interface, or release chapter it changes.
- A Sidebar or file-tree task reads Interface Shell and Library plus
  Accessibility and Adaptation; add the design-system chapter only for visual
  language, component, material, typography, color, or motion decisions.
- A Document/editor task reads Notes and Lifecycle, Document and Research
  Interface, and Accessibility and Adaptation; parser or implementation detail
  remains in Implementation Architecture.
- Release work reads Release and Open Decisions plus the current verification
  chapter rooted at [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).

Section numbers and meanings remain unique across the closed set. Git owns
replaced wording and chronology; do not retain a compatibility copy of moved
specification prose.
