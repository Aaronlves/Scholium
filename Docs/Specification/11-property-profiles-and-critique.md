# Specification: Metadata Profiles and Critique

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Appendices A–B.

## Appendix A. Default metadata profiles

Scholium separates two researcher-owned authorities. Authored YAML recognizes
only optional `summary` and `keywords`. Every other canonical structured value
uses one identity-keyed Scholium Metadata record. The managed catalog defines
shape and meaning; Analysis source-type profiles define applicability and
recommendation order; About is a role setting; exact New Note YAML defines only
authored source copied at creation; Agent-required fields apply only to typed
Analysis creation. None materializes an absent value. Every built-in seed and
Agent-required set is empty. App facts and integrations belong to neither
authority.

### Shared authored YAML

| YAML key | Shape | Rule |
| --- | --- | --- |
| `summary` | Nonempty multiline text | Short navigation description of the current Note. |
| `keywords` | Nonempty text list | Researcher-defined retrieval terms. |

Both keys are optional in Analysis, Topic, and Work. They remain authored
source and are edited in Source, not in the Metadata sheet. Any other YAML is
losslessly preserved custom source without canonical semantics, managed-field
aliases, migration, or dual reads.

### Analyses

All 52 Analysis managed fields are optional researcher-owned values. The Source
group contains choice `type`; text `title`, `short_title`, `original_title`,
`reviewed_title`, `genre`, `medium`, `version`, and `language`; and CreatorList
`authors`, `editors`, `translators`, `collection_editors`,
`container_authors`, `original_authors`, and `reviewed_authors`. The Publication
group contains source-safe date text `publication_date`,
`original_publication_date`, and `event_date`; and text `publication_status`,
`container_title`, `container_title_short`, `series_title`, `series_number`,
`volume`, `volume_title`, `issue`, `pages`, `chapter_number`, `edition`,
`number_of_volumes`, `publisher`, `publisher_place`, `original_publisher`,
`original_publisher_place`, `institution`, `report_number`, `event_title`, and
`event_place`.

| Presentation group | Managed keys and shapes |
| --- | --- |
| Access & Identifiers | source-safe date text `accessed_date`; text `doi`, `isbn`, `issn`, `url`, `pmid`, `pmcid`, `arxiv_id`, `archive`, `archive_collection`, `archive_location`, `archive_place`, `call_number` |

A CreatorList is a nonempty ordered sequence of mappings. A person requires
nonempty `family` and may have `given`, `suffix`, `non_dropping_particle`, and
`dropping_particle`. A literal creator contains only nonempty `literal`.
Person and literal forms never mix and unknown members are invalid. Scholium
does not split, invert, transliterate, or normalize names.

`type` is one of the following stable values and has one deterministic future
CSL output:

| Analysis type | CSL type |
| --- | --- |
| `journal_article` | `article-journal` |
| `book` | `book` |
| `chapter` | `chapter` |
| `encyclopedia_entry` | `entry-encyclopedia` |
| `thesis` | `thesis` |
| `manuscript` | `manuscript` |
| `report` | `report` |
| `preprint` | `article` |
| `conference_paper` | `paper-conference` |
| `presentation` | `speech` |
| `webpage` | `webpage` |
| `review` | `review-book` |
| `dataset` | `dataset` |
| `software` | `software` |
| `archival_item` | `document` |
| `correspondence` | `personal_communication` |
| `audiovisual` | `motion_picture` |
| `other` | `document` |

The built-in source-type catalog owns applicable fields and recommended order.
Journal articles, books, chapters/encyclopedia entries, theses,
manuscript/report/preprint, conference/presentation, webpages, reviews,
archival/correspondence, and dataset/software/audiovisual families use their
ordinary bibliographic fields; `other` permits the complete catalog.
Recommended is discovery order only. Settings may mark only applicable,
shape-known managed fields Agent-required; `type` is intrinsically required and
cannot be disabled. Requiredness never affects GUI New Note, researcher CLI
creation, an existing Note, or later metadata editing.

Default About order is Source `type`, `authors`; Publication
`publication_date`; then Authored YAML `summary`, `keywords`. Managed `title`
participates in Analysis identity and remains editable in Metadata but is not
repeated in About. Applicable managed fields can be added on demand without
creating or changing YAML.

### Topics

| Authority | Key | Shape | Default About | Rule |
| --- | --- | --- | --- | --- |
| Scholium Metadata | `aliases` | Nonempty text list | Topic Description | Search and link alternatives. |
| Authored YAML | `summary` | Multiline text | Authored YAML | Navigation declaration. |
| Authored YAML | `keywords` | Nonempty text list | Authored YAML | Researcher retrieval terms. |

Topic identity is first H1, then filename. YAML `title`, `aliases`,
`research_unit`, `scope`, `limitations`, and `tags` are custom source without
canonical meaning.

### Works

| Authority | Key | Shape | Default About | Rule |
| --- | --- | --- | --- | --- |
| Scholium Metadata | `work_type` | Choice | Work Description | `paper`, `chapter`, `book`, `talk`, `review`, `teaching`, or `other`. |
| Scholium Metadata | `coauthors` | Nonempty text list | Work Description | Co-authors when relevant. |
| Authored YAML | `summary` | Multiline text | Authored YAML | Navigation declaration. |
| Authored YAML | `keywords` | Nonempty text list | Authored YAML | Researcher retrieval terms. |

Work identity is first H1, then filename. YAML `title`, `work_type`,
`coauthors`, `kind`, `authors`, `venue`, `research_unit`, `scope`,
`limitations`, `tags`, `status`, and `deadline` are custom source without
canonical meaning.

### Shared presentation and settings rules

Group order is Analysis **Source → Publication → Access & Identifiers →
Authored YAML**, Topic **Topic Description → Authored YAML**, and Work **Work
Description → Authored YAML**. One catalog owns membership. Metadata and About
distinguish groups through whitespace while retaining group names for assistive
technology instead of visible repeated headings. About shows only selected,
nonempty values. Authored `keywords` render as neutral content capsules.

`settings.json` schema, exact seed, About profile, and Analysis Agent
requirements share one exact-byte revision and one atomic save. Restore About
defaults never changes seed; clearing seed never changes profiles or
requirements. Seeds contain delimiter-free YAML mapping source, normalize only
configuration newlines to LF, require a terminating LF, and preserve comments,
order, quoting, scalar style, and meaningful blank lines. Only `summary` and
`keywords` are accepted. Invalid, duplicate, reserved, unsupported, or larger
than 64 KiB in UTF-8 source cannot be saved.

## Appendix B. Bundled Critique Method requirements

The bundled Critique Skill must inspect the bounded Work context and applicable
Analyses and Topics; distinguish what those notes report, support, dispute, or
leave uncertain from the agent's own reconstruction or evaluation; and treat
neither neutral links nor transitive paths as evidence.

For the whole Work it addresses material strengths, weaknesses, method fit,
source and perspective coverage, conceptual and argumentative command,
sustained contribution, defensibility, omissions, implications, objections,
alternatives, and priorities. These are conditional burdens relative to the
Work's genre, scope, and inspected evidence, not a score or universal method.
For a selected passage it identifies the exact target, issue, significance,
research basis, and recommendation without judging the whole Work. It records
the Materials actually consulted, access limits, and uncertainty. It never
certifies novelty, publishability, doctoral level, field completeness, or
researcher competence. Any Traced, Untraced, Disputed, or Beyond Sources label
remains an attributed agent judgment, never a Scholium status.

Critique never modifies the target Work. A recommended source change requires
current Write authority. The Critique registration's editable primary Markdown
owns the active method; the app-bundled default is read only and used only for
explicit restoration. This specification states requirements without
duplicating the Skill's complete prose.
