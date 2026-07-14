# Scholium Property Profiles

**Status:** Product property vocabulary for the default workspace
**Applies to:** Analyses, Topics, and Works vaults
**Source policy:** Existing and custom YAML remains authoritative and losslessly preserved. These profiles control Scholium's recommended researcher-facing fields; they do not migrate notes or erase other properties.

## Principles

- Use a property only when it supports identification, retrieval, workflow, or an explicit research decision.
- Keep source condition separate from analysis progress, and both separate from local relevance.
- Treat note development, work production, human review, and philosophical settlement as different states.
- Keep machine identifiers, schema markers, and citation or Zotero keys available in Source mode rather than the ordinary property summary.
- Do not require YAML in Topics. A title, headings, folders, links, citations, and prose may be sufficient.
- Keep Dissertation Control on its own governed schema. Works properties do not substitute for settlement, evidence, privacy, or prose-permission controls.

## Vault-wide presentation

Scholium starts with one profile for each Triptych vault. In **Settings → Properties**, the researcher may set the visible fields and their order, the human-editable allowlist, and whether the Properties disclosure starts open. Each configuration applies to the complete Analyses, Topics, or Works vault; Scholium provides no folder-level or note-level override.

The configuration changes only Scholium's projection and targeted editing affordances. It never sorts, migrates, removes, or otherwise rewrites frontmatter. Machine identity, Zotero linkage keys, provenance, fingerprints, and automatically maintained history remain protected in structured controls; exact YAML remains available in Source mode.

## Shared Triptych keys

Analyses, Topics, and Works use one compact YAML vocabulary wherever the same idea recurs: `title`, `tags`, `status`, `created`, and `updated`. Analyses and Works also share `authors`. Analyses may use `type` for the form of the analyzed source; Works may use `kind` for the form of the researcher’s output. A shared key names the same broad kind of fact, while its allowed values and precise meaning remain scoped to the vault role. For example, `status` tracks analysis progress in Analyses, note development in Topics, and production state in Works.

## Analyses

Analyses describe a source-facing reconstruction or assessment. Bibliographic identity is the only required researcher-facing metadata.

| Group | Property | YAML key | Shape | Purpose |
| --- | --- | --- | --- | --- |
| About | Title | `title` | text, required | Title of the analyzed source. |
| About | Authors | `authors` | list, required | Source authors. |
| About | Year | `year` | number, required | Publication year. |
| About | Type | `type` | controlled text | Publication form, not philosophical role. |
| About | Tags | `tags` | list | Lightweight retrieval terms. |
| Source | Access | `access` | controlled text | How much source material was available. |
| Source | Text Reliability | `text_reliability` | controlled text | Reliability of the consulted text. |
| Source | Locators | `locators` | controlled text | Whether citations have stable, checkable locations. |
| Progress | Status | `status` | controlled text | `draft`, `complete`, or `reviewed`. |
| Use | Relevance | `relevance` | integer, 1–10 | Local research relevance; never source quality. |
| History | Created | `created` | date | Analysis creation date when recorded. |
| History | Updated | `updated` | date | Mechanical analysis update date. |

Folders, tags, links, and citations carry topic placement and follow-up context without duplicating them as analysis properties. Nested audit data and machine linkage may remain in exact YAML. Scholium displays structured audit data read-only rather than flattening and rewriting it.

## Topics

Topics are evolving concept, problem, debate, or synthesis notes. YAML is optional, and the profile is intentionally small.

| Group | Property | YAML key | Shape | Purpose |
| --- | --- | --- | --- | --- |
| About | Title | `title` | text | Optional when filename and H1 already identify the topic. |
| About | Aliases | `aliases` | list | Alternative names used in search and links. |
| About | Tags | `tags` | list | Lightweight retrieval terms. |
| Progress | Status | `status` | controlled text | Note development: `seed`, `developing`, or `maintained`; not philosophical settlement. |
| History | Created | `created` | date | Preserved when already used. |
| History | Updated | `updated` | date | Preserved when already used; Scholium does not inject topic YAML. |

Source support belongs in citations, footnotes, callouts, and source-anchored links. A topic property must not claim that cited material supports the note merely because a link exists.

## Works

Works are researcher-authored outputs such as articles, chapters, books, talks, reviews, and teaching materials.

| Group | Property | YAML key | Shape | Purpose |
| --- | --- | --- | --- | --- |
| About | Title | `title` | text, required | Title of the work. |
| About | Authors | `authors` | list | Co-authors when applicable. |
| About | Kind | `kind` | controlled text | Form of the authored work, such as paper, chapter, book, talk, review, or teaching material. |
| About | Tags | `tags` | list | Lightweight retrieval terms. |
| Progress | Status | `status` | controlled text | `planning`, `drafting`, `revising`, `review`, `ready`, `submitted`, `published`, or `archived`. |
| Use | Venue | `venue` | text | Intended or actual journal, publisher, course, or event. |
| Use | Deadline | `deadline` | date | Relevant delivery or submission date. |
| History | Created | `created` | date | Creation date when recorded. |
| History | Updated | `updated` | date | Mechanical update date. |

Works status records production state only. It does not encode argumentative quality, evidential sufficiency, acceptance probability, or a dissertation-control decision.

Works folders carry researcher-defined grouping. Scholium does not add a `project` property, register project membership, or infer a project from this profile.

## Compatibility

Legacy keys remain readable and stay untouched during ordinary saves. When a researcher deliberately edits one recognized property, Scholium writes that property under its canonical Triptych key and removes only the corresponding legacy alias; it does not bulk-migrate the note. Other non-machine fields remain visible as custom properties, and exact YAML stays available in Source mode. Internal and CLI role identifiers remain stable for registry and automation compatibility even when the interface says Analyses, Topics, and Works.
