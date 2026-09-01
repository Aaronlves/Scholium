# Scholium Specification

- **Status:** Canonical product, interface, and release specification
- **Applies to:** Scholium for macOS and its local MCP/CLI adapter

This file is the sole entry point and closed manifest for target product
behavior. Only the chapters below are normative. Structural ownership belongs
to [IMPLEMENTATION_ARCHITECTURE.md](IMPLEMENTATION_ARCHITECTURE.md); dated
reachability and evidence belong to
[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md). Apple HIG and the selected
SDK own platform conventions; this set owns Scholium's research semantics.

## Set contract

The specification contains stable target behavior, terminology, interface and
accessibility requirements, release gates, and unresolved target questions. It
does not contain implementation structure, current reachability, test results,
operator instructions, or decision history. Architecture and status documents
must not create alternative product rules.

## Canonical chapters

| Chapter | Owns |
| --- | --- |
| [Foundation and Triptych](Specification/01-foundation-and-triptych.md) | §§1–4: terminology, authority, Triptych, and Works organization. |
| [Notes and File Operations](Specification/02-notes-and-file-operations.md) | §§5–7: Note behavior, file operations, deletion, Settle, and annotation. |
| [Agent Collaboration and Research Workflows](Specification/03-agent-collaboration-and-workflows.md) | §§8–11: MCP/Core Protocol collaboration and the Analysis, Topic, and Work workflows. |
| [Connect, Search, and Recovery](Specification/04-connect-search-and-recovery.md) | §§12–14: Connections, Search, Attention, save, and recovery. |
| [Integrations, Onboarding, and Boundaries](Specification/05-integrations-onboarding-and-boundaries.md) | §§15–17: Zotero, onboarding, permanent boundaries, and deferrals. |
| [Interface Shell and Library](Specification/06-interface-shell-and-library.md) | §§18.1–18.3: shell, Library, and Search presentation. |
| [Document and Research Interface](Specification/07-document-and-research-interface.md) | §§18.4–18.7: Document, Inspector, Records, states, and terminology. |
| [Scholium Design](../Design.md) | §19: visual language, Variables, components, patterns, motion, and writing. |
| [Accessibility and Adaptation](Specification/09-accessibility-and-adaptation.md) | §20: cross-cutting accessibility and adaptation. |
| [Release and Open Decisions](Specification/10-release-and-open-decisions.md) | §§21–22: release requirements and unresolved target questions. |
| [Metadata and Critique](Specification/11-metadata-and-critique.md) | Appendices A–B: metadata catalogs and bundled Critique requirements. |

## Reading routes

Read this manifest, then the owning workflow chapter. Add the relevant interface
and accessibility chapters for user-facing changes, §19 for visual-language
changes, and §21 plus current implementation status for release work.
Architecture owns parser, module, runtime, and persistence mechanics.

Section meanings are unique across this set. Put each rule in one owning
chapter and link to it instead of restating it.
