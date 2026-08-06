# Implementation Architecture

- **Scope:** module, runtime, state-ownership, and delivery boundaries
- **Target authority:** [SCHOLIUM_SPEC.md](SCHOLIUM_SPEC.md)

This file is the sole entry point and closed manifest for Scholium's
subordinate implementation architecture. The chapters listed below describe
how current code is divided and how mutable state flows through it. They do not
redefine product workflows, interface labels, visual decisions, vault formats,
or research-governance rules.

Architecture records the current structural model only. It may name modules,
types, stores, actors, dependencies, and runtime transactions when those names
clarify ownership. It does not retain superseded alternatives, completed
migration plans, decision chronology, test counts, timings, acceptance
results, or release evidence. Git owns structural history.

[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) owns dated conformance and
verification evidence; the package graph, live code, tests, and scripts remain
the final implementation evidence.

## Architecture chapters

| Chapter | Owns |
| --- | --- |
| [Runtime and Ownership](Architecture/01-runtime-and-ownership.md) | Compiler/runtime composition, module dependencies, state owners, windows, refresh, Library mutations, tabs, and shell construction. |
| [Research Actions and Execution](Architecture/02-research-actions-and-execution.md) | Action preparation, protected execution, Research Records, permissions, agent coordination, and completion/recovery. |
| [Source Layout and Presentation](Architecture/03-source-layout-and-presentation.md) | Repository source layout, native presentation composition, window routes, Attention, Research Inspector, and localization. |
| [Research Guidance](Architecture/04-research-guidance.md) | Method/Practice registration, academic Profiles, collaboration policy, citation configuration, Settings, and configuration recovery. |
| [Source Storage and Read Models](Architecture/05-source-storage-and-read-models.md) | Descriptor-relative source writes, macOS coordination, prewrite recovery, immutable Note snapshots, metadata, and targeted YAML edits. |
| [Documents and Editor](Architecture/06-documents-and-editor.md) | Document sessions, CodeMirror/WebKit, exact-source mirroring, rendering, interaction, recovery, and performance boundaries. |
| [Design System and Boundary Enforcement](Architecture/07-design-system-and-boundaries.md) | Semantic design-system implementation, component ownership, import guards, and executable architecture checks. |

## Reading routes

Read only the chapter that owns the responsibility under change, then add a
neighbor when the live call path crosses that boundary. Cross-layer work starts
with Runtime and Ownership; source-safety work adds Source Storage and Read
Models; editor work adds Documents and Editor; application-interface work adds
Source Layout and Presentation. Dated measurements and acceptance remain in
Implementation Status rather than these chapters.

Every architecture fact has one owning chapter. A chapter split is file
organization only: it creates no new runtime, module, state owner, transaction,
or compatibility path.
