# Implementation Architecture

- **Scope:** module, runtime, state-ownership, and delivery boundaries
- **Target authority:** [SCHOLIUM_SPEC.md](SCHOLIUM_SPEC.md)

This is the sole entry point and closed manifest for current module, runtime,
dependency, state-owner, persistence, and delivery structure. Architecture may
name concrete implementation owners when that clarifies responsibility, but it
does not redefine product behavior or retain alternatives, migration narrative,
test results, or release evidence. Target authority is
[SCHOLIUM_SPEC.md](SCHOLIUM_SPEC.md); dated conformance belongs to
[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).

## Architecture chapters

| Chapter | Owns |
| --- | --- |
| [Runtime and Ownership](Architecture/01-runtime-and-ownership.md) | Compiler/runtime composition, module dependencies, state owners, windows, refresh, Library mutations, tabs, and shell construction. |
| [Agent Collaboration](Architecture/02-agent-collaboration.md) | Local MCP delivery, attributed Research Records, guarded Note mutations, Agent Change evidence, and setup/presentation. |
| [Source Layout and Presentation](Architecture/03-source-layout-and-presentation.md) | Repository source layout, native presentation composition, window routes, Attention, Research Inspector, and localization. |
| [Research Guidance](Architecture/04-research-guidance.md) | Agent Integration, Zotero configuration, and Settings ownership. |
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
