---
name: scholium-citation-verification
description: Editable researcher-owned starter method for verifying bibliographic metadata, quotations, locators, editions, one-source/one-claim support, and APA 7 citation form. Use when a Scholium task needs atomic citation verification rather than full source analysis, philosophical content audit, or manuscript review. Adapt or replace its style rules when another discipline, language, edition practice, or venue governs.
---

# Citation Verification — APA 7 Starter

Apply `scholium-core-protocol`. This is an editable Researcher Skill template, not a universal Scholium authority. Its default formatting convention is APA 7; the researcher owns any adopted copy and may revise or replace it.

## Establish the verification packet

```text
Focus: metadata | quotation-and-locator | claim-support | apa-7 | combined
Citation or source:
Exact claim or quotation, when applicable:
Source version or edition:
Available source material:
Requested style or venue rule:
Read set:
Write set:
Permission:
Output:
Stop condition:
```

Use `scholium-zotero-integration` when bounded Zotero retrieval is needed, but do not treat a Zotero record as source evidence. If the source itself must be analyzed, request the necessary source material outside Actions. Use `scholium-content-fidelity` when the larger question is whether prose stays within verified scope and assigns the source a warranted philosophical role.

## Load the method

Read [references/verification-method.md](references/verification-method.md) completely for every substantive check. Read [references/apa-7-starter.md](references/apa-7-starter.md) only when APA 7 form is requested. Never use APA merely because no other convention was supplied.

## Execute

1. Identify the exact source, version, edition, translation, and locator system.
2. Separate metadata verification, quotation verification, locator verification, and claim-support verification.
3. Check the highest-priority available evidence rather than completing missing facts from memory.
4. For claim support, state what the source supports, at what scope, and what it does not support.
5. Apply the requested style only after source identity and locator facts are verified.
6. Preserve unresolved uncertainty and identify the smallest next check.
7. During Check Fidelity, remain read-only and return atomic corrections. Apply them only through a later Analyze, Synthesize, or Write run with fresh authority and exact-note recovery.

## Return

```text
Citation or source:
Verification focus:
Verification status: verified | provisional | unavailable
Source version or edition:
Metadata status:
Quotation status:
Locator status:
Claim-support verdict: yes | partly | no | unclear | not assessed
Evidence basis:
Formatted citation, when requested:
In-text citation form, when requested:
Unresolved risk:
Next verification step:
```

Never invent bibliographic details, quotations, locators, DOI or ISBN values, publication facts, source positions, or style-specific punctuation. If the source text is unavailable, do not claim that a quotation, locator, or source-support relation has been verified.

Use `verified` only when the requested atomic questions were checked against sufficient evidence. Use `provisional` when some useful check was possible but access, identity, edition, locator, or context remains incomplete. Use `unavailable` when the requested verification could not responsibly be performed. State which fields remain unresolved.

Handle chapters in edited volumes, editions and translations, canonical locators, complete author order, same-author/year disambiguation, and quotation versus close paraphrase as distinct boundary cases. Do not collapse chapter authorship into volume editorship or silently transfer a locator across editions.
