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
Treat that immutable snapshot as the complete Zotero context for the run. Do
not probe, search, inspect the item again, fetch an attachment, or replace the
snapshot with newer library state. A warning in the snapshot is nonblocking:
continue from available sources and fill only information genuinely needed by
the Action. Abstract, tags, and Collections remain metadata rather than
paper content or philosophical evidence. Never copy the snapshot into Markdown.

The remaining sections govern explicit external-agent Zotero operations when
no prepared snapshot supplies the bounded result.

## Supported MCP transport

Scholium's supported transport is the installed Scholium CLI or MCP adapter, including the first-party `scholium zotero mcp serve` stdio service. Use `scholium zotero mcp config --format json` for the external-agent configuration and `scholium zotero mcp status` to report command availability; add `--probe` only for the data-free MCP initialize lifecycle. If the installed adapter is unavailable, report that limitation rather than searching developer directories or trying to build Scholium.

The first-party service uses Zotero Desktop's loopback API for readiness, search, item inspection, and explicitly requested bounded attachment pointers. That API is read-only. BibTeX and RIS imports use Zotero's localhost Connector and require an exact-content dry run; the returned authorization token is short-lived, one-shot, and bound to the content hash and selected destination. The confirmed call rechecks the destination and then reads every returned item back through the local API. No Zotero Web API key is required or stored. Scholium's built-in UI remains read-only and never inherits this external-agent write capability.

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
7. For an import, require an explicit current-task request, verify the selected target, preview the exact unchanged record, then make the real call only with `confirm=true`, `dry_run=false`, and the one-shot authorization token returned by that preview.
8. Re-read the resulting item after an import and report any mismatch in item type, creators, title, dates, identifiers, destination, or citation key.

## Non-negotiable boundaries

- Do not scan global agent configuration or arbitrary filesystem locations to find a Zotero integration.
- Do not read or write `zotero.sqlite` directly.
- Do not change Zotero preferences, install connectors, start a hidden service, or select a destination on the researcher's behalf.
- Do not infer import permission from a request to analyze, cite, verify, search, or open a source.
- Do not silently select among ambiguous matches or destinations.
- Do not claim that a Zotero record verifies a quotation, page locator, argument, definition, or interpretation.
- Do not impose a citation style. Use a researcher-installed citation skill when formatting conventions matter.

## Handoff

Return only the Zotero facts needed by the selected Method Skill: stable identity, checked metadata, access status, attachment pointer when permitted, and unresolved ambiguity. Keep Zotero operations out of the permanent scholarly record except when their success, failure, or ambiguity affects the research result.

If retrieved source material needs full source analysis in an Analysis, prepare Analyze with exact source access. If verified material should enter a Topic or Work, prepare Synthesize or Write with fresh Target and Material revisions. Zotero retrieval itself grants none of those writes.
