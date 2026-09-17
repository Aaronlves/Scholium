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
| [Runtime and Ownership](Architecture/01-runtime-and-ownership.md) | Module/runtime ownership, workspace publication, Library/window lifetimes, presentation routing, Settings, localization, and shared delivery boundaries. |
| [Agent Collaboration](Architecture/02-agent-collaboration.md) | Local MCP delivery, guarded Note mutations, Agent Change evidence, and setup/presentation. |
| [Source Storage and Read Models](Architecture/05-source-storage-and-read-models.md) | Descriptor-relative source writes, macOS coordination, prewrite recovery, immutable Note snapshots, metadata, and targeted YAML edits. |
| [Documents and Editor](Architecture/06-documents-and-editor.md) | Document sessions, CodeMirror/WebKit, exact-source mirroring, rendering, interaction, recovery, and performance boundaries. |

## Reading routes

Read only the chapter that owns the responsibility under change, then add a
neighbor when the live call path crosses that boundary. Cross-layer work starts
with Runtime and Ownership; source-safety work adds Source Storage and Read
Models; editor work adds Documents and Editor; application-interface work follows
Runtime and Ownership's window and presentation boundaries. Dated measurements and acceptance remain in
Implementation Status rather than these chapters.

Every architecture fact has one owning chapter. A chapter split is file
organization only: it creates no new runtime, module, state owner, transaction,
or compatibility path.
