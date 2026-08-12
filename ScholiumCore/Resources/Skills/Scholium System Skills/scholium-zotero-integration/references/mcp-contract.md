# Zotero MCP Capability Contract

This reference describes capabilities, not hard-coded MCP server or tool names. Select only a configured local tool whose declared operation matches the required capability.

## Capability map

| Capability | Purpose | Default effect |
| --- | --- | --- |
| Status | Report Zotero, local API, connector, and library readiness | Read-only |
| Search | Find candidate records by title, creator, year, DOI, ISBN, citation key, or other supported metadata | Read-only |
| Item inspection | Return one exact item's metadata and, when requested, bounded attachment pointers | Read-only |
| Selected target | Report the library or collection currently selected for an import | Read-only |
| BibTeX import | Import exact BibTeX supplied in the current task | Write; guarded |
| RIS import | Import exact RIS supplied in the current task | Write; guarded |

The Beta integration must expose equivalent capabilities through stable, documented MCP tools. The System Skill must route by capability so a release can change internal tool names without changing the scholarly workflow.

The installed MCP tool schemas own current tool names, input fields, and return
shapes. Route by the declared capability rather than copying those volatile
details into this contract. An MCP initialize response establishes the
transport only; the Status capability separately establishes Zotero API and
Connector readiness.

## Retrieval protocol

1. Call Status first unless readiness was established in the current uninterrupted operation.
2. Search using stable identifiers when available. A DOI, ISBN, or exact item key is stronger than title keywords.
3. Preserve multiple plausible matches. Do not choose by rank alone.
4. Inspect the selected item and retain the identifiers used to establish identity.
5. Report missing, stale, or contradictory metadata rather than repairing it silently.

Zotero metadata can establish which record was found. It cannot establish what a source argues. Abstracts, notes, tags, and citation metadata must not be presented as if they were verified full-text evidence.

## Source-access protocol

An attachment pointer identifies possible source material; it is not proof that the attachment is the correct version or that its text is extractable.

When source access is required:

- verify the parent item and attachment relation;
- identify the version when possible;
- record whether full text, an abstract, an excerpt, or metadata only was available;
- check selectable-text and pagination reliability before using page-specific locators;
- pass the source packet to an explicitly selected external source-analysis method rather than analyzing it inside this adapter; Scholium does not expose Source Analysis as a Strip function.

## Guarded import protocol

A real import is permitted only when all of the following hold:

1. The current researcher instruction explicitly asks to import the exact supplied record or records.
2. The MCP capability reports the exact selected Zotero library or collection target.
3. Ambiguity about the record, item type, or destination has been resolved by the researcher.
4. A dry run of the exact unchanged import text has succeeded and its preview
   matches the intended operation.
5. The real tool call explicitly confirms a non-dry-run import with the
   unexpired one-shot authorization returned by that dry run. The authorization
   must be bound to the content hash and selected destination.
6. The result is re-read and checked after the write.

Do not convert an analysis, bibliography check, citation request, or earlier import into standing write permission. If the tool lacks a target-bound dry run, one-shot authorization, explicit confirmation, and read-back controls, treat imports as unavailable.

## Verification after import

Check at least:

- destination library or collection;
- item count and item type;
- title and creators;
- publication and date fields;
- DOI, ISBN, URL, or other primary identifier;
- citation key when available;
- duplicate or partial-import warnings.

Report the exact verified result and any fields requiring researcher correction. Never repair the live Zotero database directly.

## Failure behavior

Name the exact failing boundary when known: MCP capability unavailable, Zotero not running, local communication disabled, connector unavailable, no match, ambiguous match, no selected target, dry-run failure, write unconfirmed, import failure, or verification mismatch.

Do not bypass a failed MCP route through raw database access. Continue from researcher-supplied files or already authorized source material only when that remains sufficient for the original task.
