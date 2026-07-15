# Citation-Verification Method

## Keep atomic questions separate

Distinguish:

- **bibliographic identity** — author, title, year, venue, publisher, edition, translator, DOI, ISBN, and item type;
- **quotation fidelity** — exact words, omissions, interpolation, punctuation, capitalization, and surrounding context;
- **locator fidelity** — printed page, section, paragraph, canonical numbering, or another stable locator in the exact version consulted;
- **claim support** — whether that exact source supports the exact claim at the strength, scope, and dialectical role assigned to it;
- **citation form** — how verified facts should be represented under a specified style.

A correct reference-list entry does not prove that the source supports a claim. A source-support verdict does not establish the philosophical adequacy of the surrounding argument.

## Evidence priority

Use the highest applicable layer:

1. the exact primary or published source version inspected with sufficient context;
2. an authoritative publisher, DOI registry, library, journal, or edition record for bibliographic identity;
3. a verified excerpt with a stable locator and enough surrounding context;
4. a saved Analysis as a locator lead or reconstruction, not a substitute for the source when direct verification is required;
5. Zotero metadata as a retrieval aid that still requires verification when material consequences follow.

Search public sources only under the privacy boundary in `scholium-core-protocol`. Search snippets and generated summaries are not verification evidence.

## Claim-support procedure

For one source and one claim:

1. State the claim exactly and identify its required strength.
2. Locate the source passage or result allegedly supporting it.
3. Read enough surrounding context to recover qualifications, targets, objections, and authorial status.
4. Distinguish the author's explicit claim, report of another view, source-supported reconstruction, and an analyst's inference.
5. Compare scope, modality, terminology, and dialectical role.
6. Return `yes`, `partly`, `no`, or `unclear`, with the evidence and limitation.
7. State explicitly what stronger claim or role the source does not establish.

Do not infer support, criticism, influence, or debate participation from citation, keyword overlap, graph proximity, or similar wording.

## Quotations and locators

- Verify against the exact edition or version used by the researcher.
- Distinguish printed pagination from PDF pagination.
- Inspect rendered pages when OCR or extraction may corrupt names, symbols, punctuation, footnotes, or line breaks.
- Preserve omissions and insertions transparently.
- If editions use incompatible locators, name the edition and do not silently translate page numbers.

## Status language

Use one of:

- `verified`;
- `partly verified`;
- `unverified`;
- `probably wrong`;
- `unsupported by available evidence`;
- `needs page check`;
- `needs edition check`.

State why the status applies. A status label without evidence is not a verification result.
