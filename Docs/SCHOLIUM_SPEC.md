# Scholium Specification

- **Status:** Canonical product, interface, and release specification
- **Applies to:** Scholium for macOS and its local App-bundled MCP adapter

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
| [Notes and File Operations](Specification/02-notes-and-file-operations.md) | §§5–7 and Appendix A: Note behavior, file operations, deletion, Settle, annotation, and authored source properties. |
| [Agent Collaboration and Research Workflows](Specification/03-agent-collaboration-and-workflows.md) | §§8–8.6, 9–11: MCP/Core Protocol collaboration and the Analysis, Topic, and Work workflows. |
| [In-app Agent Chat](Specification/12-agent-chat.md) | §8.7: conversations, runtime capabilities, materials, Skills, execution and recovery. |
| [Connect, Search, and Recovery](Specification/04-connect-search-and-recovery.md) | §§12–14: Connections, Search, Attention, save, and recovery. |
| [Integrations, Onboarding, and Boundaries](Specification/05-integrations-onboarding-and-boundaries.md) | §§15–17: Zotero, onboarding, permanent boundaries, and deferrals. |
| [Interface Shell and Library](Specification/06-interface-shell-and-library.md) | §§18.1–18.3: shell, Library, and Search presentation; Settings is declared separately below. |
| [Chat Interface](Specification/14-chat-interface.md) | §18.2.2: conversation list, composer, transcript, materials and runtime-control presentation. |
| [Settings](Specification/13-settings.md) | §18.2.1: settings navigation, scope, page composition, controls, writing, and change feedback. |
| [Document and Research Interface](Specification/07-document-and-research-interface.md) | §§18.4–18.7: Document, Inspector, shared state language, and terminology. |
| [Scholium Design](../Design.md) | §19: stable global design philosophy, native/Liquid Glass relationship, background and Accent identity. |
| [Accessibility and Adaptation](Specification/09-accessibility-and-adaptation.md) | §20: cross-cutting accessibility and adaptation. |
| [Release and Open Decisions](Specification/10-release-and-open-decisions.md) | §§21–22: release requirements and unresolved target questions. |

## Reading routes

Read this manifest, then the chapter that owns the question:

| Question | Reading route |
| --- | --- |
| Product role and researcher responsibility | Foundation §§1–4; Boundaries §17. |
| Source editing, file operations and recovery | Notes §§5–7; Recovery §14; Document §18.4. |
| External Agent access | Collaboration §8; distribution §21.5. |
| In-app Chat behavior and presentation | Chat §8.7; Chat Interface §18.2.2. |
| Retrieval and authored links | Connect/Search §§12–13; Inspector §18.5. |
| Native shell and preferences | Shell §§18.1–18.3; Settings §18.2.1. |
| Release scope and outstanding evidence | Release §21; Implementation Status. |

For interface changes add §20, and read Design only when the visual-language
boundary is affected. Feature chapters own behavior; they reference shared
presentation, accessibility and release rules instead of duplicating them.
Architecture owns parser, module, runtime, and persistence mechanics.

## Single-owner editing rule

| Content | Sole owner |
| --- | --- |
| Global design philosophy and identity | Design (§19); Agent edit admission and size limits are owned by AGENTS.md. |
| Research meaning, authority and operations | Owning workflow chapter (§§1–17); interface chapters link to it. |
| Feature layout, interaction and state wording | Owning interface section (§§18.1–18.7). |
| Authored YAML properties and retrieval | Notes §5.2 and Appendix A. |
| Accessibility requirements and human acceptance method | §20; feature chapters add no parallel checklist. |
| Release profiles, gates and artifact requirements | §21; status records evidence only. |
| Current implementation owners and mechanisms | Architecture set; source holds exact local defaults. |
| Implementation scope, remaining work and dated proof | Status entry snapshot, Open Work and Verification respectively. |

Put each rule in that owner and link from consumers. Move a rule rather than
copying it; remove superseded wording in the same edit. Do not carry obsolete
alternatives or completed change narratives into canonical documents. Git owns
history. A change to target prose is not evidence that the app implements it.
The [Design edit boundary](../AGENTS.md#design-document-change-boundary) applies
to every Agent; a feature chapter cannot create an exception to the global charter.
