---
name: scholium-zotero-integration
description: Use Scholium's protected Zotero MCP contract when an external agent must inspect a researcher's Zotero library, resolve source identity, obtain bounded metadata or attachment pointers, or perform an explicitly requested guarded BibTeX or RIS import. Use only with a configured local Zotero MCP capability; do not use as a citation-style authority, source-analysis substitute, or reason to treat metadata as source evidence.
---

# Scholium Zotero Integration

Apply `scholium-core-protocol`. This protected System Skill governs how an external agent uses Scholium's supported local Zotero MCP capability. It is an application adapter, not a philosophical method, citation formatter, source-analysis workflow, or Zotero replacement.

The skill file supplies the instruction contract; it does not itself create an MCP transport. If the supported Zotero MCP capability is unavailable, report that exact limitation and continue only from sources already available within the task.

## Prepared Analyze Action

When a prepared packet contains a labelled **Zotero bibliographic metadata**
snapshot, Application has already performed the one permitted exact item read.
Treat that immutable snapshot as the complete Scholium-managed metadata context
for the run. Do not probe, search, inspect the item again, or replace the
snapshot with newer library state. This does not prohibit the Agent from using
the configured Zotero/MCP capability to retrieve the exact bound attachment or
paper data required by Analyze; that retrieval remains outside Scholium's
source-access store and must be reported with its extraction limits. A warning
in the snapshot is nonblocking: continue from available sources and fill only
information genuinely needed by the Action. Abstract, tags, and Collections
remain metadata rather than paper content or philosophical evidence. Never
copy the snapshot into Markdown.

The remaining sections govern explicit external-agent Zotero operations and
paper retrieval not supplied by Scholium's frozen metadata snapshot.

## Portable Analysis binding

An authenticated Run may record and perform `set_zotero_binding` or
`clear_zotero_binding` for one current Analysis target. This operation belongs
to the Run's tracked activity, not to MCP and not to Markdown or Properties.
Use the installed `scholium agent write-zotero-binding` help for the current
strict payload. Set only an exact library identity and item key established by
the researcher or by a permitted, unambiguous current-task Zotero operation;
clear only when the current task requires removing the relationship. Reload
after conflict or uncertain recovery state.

The command changes only Scholium's portable relationship. It does not write
the Zotero library, fetch source content, create bibliographic evidence, or
authorize another Note. If identity is ambiguous or the exact member and
operation are not returned as ready, stop rather than guessing or using a
document write.

## Supported MCP transport

Scholium's supported transport is the installed Scholium CLI or its configured
local MCP adapter. Use the installed CLI help and the MCP tool schemas as the
only authority for current invocation syntax and fields. If the installed
adapter is unavailable, report that limitation rather than searching developer
directories or trying to build Scholium.

The first-party service uses Zotero Desktop's loopback API for readiness, search, item inspection, and explicitly requested bounded attachment pointers. That API is read-only. BibTeX and RIS imports use Zotero's localhost Connector and require an exact-content dry run; the returned mutation token is short-lived, one-shot, and bound to the content hash and selected destination. The confirmed call rechecks the destination and then reads every returned item back through the local API. No Zotero Web API key is required or stored. Scholium's built-in UI remains read-only and never inherits this external-service mutation path.

The MCP initialize handshake proves only that the stdio service exists. It does not prove that Zotero is open or that its API and Connector are ready; call the Status capability before a Zotero operation. Route by the capability contract in `references/mcp-contract.md` rather than assuming that an instruction file is a connection.

## Establish the Zotero operation

Add the following fields to the task packet:

```text
Zotero operation: status | search | inspect-item | selected-target | import-bibtex | import-ris
MCP capability status: unknown | available | unavailable
Library write requested: no | yes-explicitly
Target library or collection:
Record or import source:
Dry run required: no | yes
Verification required:
```

Retrieval is the default. A request to analyze a paper, verify a citation, or search the library does not authorize a Zotero write.

## Load the capability contract

Read [references/mcp-contract.md](references/mcp-contract.md) completely before calling a Zotero MCP tool.

## Operate safely

1. Probe the configured Zotero MCP capability before assuming that Zotero, its local API, or its connector is ready.
2. Search with the narrowest useful bibliographic query. Preserve ambiguity and ask the researcher to choose when identity cannot be established reliably.
3. Inspect the exact item before relying on its metadata or attachment pointers.
4. Distinguish the Zotero item key from a citation or BibTeX key.
5. Treat library metadata as identity and retrieval information, not as evidence for a paper's philosophical claims.
6. Retrieve attachment pointers or full text only when the task requires source access and the researcher-authorized read set permits it. Record extraction and locator reliability separately.
7. For an import, require an explicit current-task request, verify the selected target, preview the exact unchanged record, then make the real confirmed call only with the one-shot authorization returned by that preview.
8. Re-read the resulting item after an import and report any mismatch in item type, creators, title, dates, identifiers, destination, or citation key.

## Non-negotiable boundaries

- Do not scan global agent configuration or arbitrary filesystem locations to find a Zotero integration.
- Do not read or write `zotero.sqlite` directly.
- Do not change Zotero preferences, install connectors, start a hidden service, or select a destination on the researcher's behalf.
- Do not infer import permission from a request to analyze, cite, verify, search, or open a source.
- Do not silently select among ambiguous matches or destinations.
- Do not claim that a Zotero record verifies a quotation, page locator, argument, definition, or interpretation.
- Do not impose a citation style. Use the current Triptych citation-style Platform setting when formatting conventions matter.

## Handoff

Return only the Zotero facts needed by the selected Method Skill: stable identity, checked metadata, access status, attachment pointer when permitted, and unresolved ambiguity. Keep Zotero operations out of the permanent scholarly record except when their success, failure, or ambiguity affects the research result.

If retrieved source material needs full source analysis in an Analysis, an
Agent-originated Analyze Run may use the external paper-data route without a
Scholium `sourceReference`; alternatively, a GUI-prepared Analyze Run may use
Scholium's exact source-access route. In both cases report the exact material
retrieved, extraction limits, and uncertainty. If verified material should
enter a Topic or Work, prepare Synthesize or Write with fresh Target and
Material revisions. Zotero retrieval itself grants none of those writes.
