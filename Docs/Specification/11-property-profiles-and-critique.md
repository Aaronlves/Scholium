# Specification: Property Profiles and Critique

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Appendices A–B.

## Appendix A. Default property profiles

Existing/custom YAML remains authoritative and losslessly preserved. Canonical
vocabulary defines recognized shape and meaning; source-type profiles define
applicability, recommendation, and serialization order; About is a role
setting; exact New Note YAML defines only source
copied at creation; Agent-required fields apply only to typed Analysis create.
None materializes an absent key. Every built-in seed and Agent-required set is
empty. App facts and integrations remain outside frontmatter.

### Analyses

All 56 supported keys are optional researcher-owned top-level properties. The
Source group contains choice `type`; text `title`, `short_title`,
`original_title`, `reviewed_title`, `genre`, `medium`, `version`, and
`language`; and CreatorList `authors`, `editors`, `translators`,
`collection_editors`, `container_authors`, `original_authors`, and
`reviewed_authors`. The Publication group contains source-safe date text
`publication_date`, `original_publication_date`, and `event_date`; and text
`publication_status`, `container_title`, `container_title_short`,
`series_title`, `series_number`, `volume`, `volume_title`, `issue`, `pages`,
`chapter_number`, `edition`, `number_of_volumes`, `publisher`,
`publisher_place`, `original_publisher`, `original_publisher_place`,
`institution`, `report_number`, `event_title`, and `event_place`.

| Presentation group | Canonical keys and shapes |
| --- | --- |
| Access & Identifiers | source-safe date text `accessed_date`; text `doi`, `isbn`, `issn`, `url`, `pmid`, `pmcid`, `arxiv_id`, `archive`, `archive_collection`, `archive_location`, `archive_place`, `call_number` |
| Research | nonempty text lists `source_basis`, `limitations`; multiline text `summary` |
| Tags | nonempty text list `tags` |

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

The built-in source-type catalog owns applicable fields, recommended order,
and deterministic serialization order. Journal articles, books,
chapters/encyclopedia entries, theses, manuscript/report/preprint,
conference/presentation, webpages, reviews, archival/correspondence, and
dataset/software/audiovisual families use their ordinary bibliographic fields;
`other` permits the complete catalog. Research fields apply to every type.
Recommended is discovery order only. Settings may mark only applicable,
shape-known fields Agent-required; `type` is intrinsically required and cannot
be disabled. A seed collision is invalid. Requiredness never affects GUI New
Note, researcher CLI creation, an existing Note, or later property permission.

Default About order is Source `type`; Publication `publication_date`; Research
`limitations`, `summary`, `source_basis`; then Tags. `title` remains visible in
Complete Properties and participates in Analysis identity but is not repeated
in About. Applicable canonical fields can be added on demand without creating
empty YAML, and present source-safe values can be edited directly.

### Topics

Topic YAML is optional.

| YAML | Shape | Default About | Rule |
| --- | --- | --- | --- |
| `aliases` | Nonempty text list | Topic Description | Search and link alternatives. |
| `summary` | Multiline text | Topic Description | Navigation declaration. |
| `limitations` | Nonempty text list | Research | Material boundaries. |
| `tags` | Nonempty text list | Tags | Researcher retrieval terms. |

All four fields are directly editable when their exact source shape is safe.
Topic identity is first H1, then filename. YAML `title`, `research_unit`, and `scope` are not
recognized.

### Works

| YAML | Shape | Default About | Rule |
| --- | --- | --- | --- |
| `work_type` | Choice | Work Description | `paper`, `chapter`, `book`, `talk`, `review`, `teaching`, or `other`. |
| `coauthors` | Nonempty text list | Work Description | Co-authors when relevant. |
| `summary` | Multiline text | Work Description | Navigation declaration. |
| `limitations` | Nonempty text list | Research | Material boundaries. |
| `tags` | Nonempty text list | Tags | Researcher retrieval terms. |

All five fields are directly editable when their exact source shape is safe.
Work identity is first H1, then filename. YAML `title`, `kind`, `authors`, `venue`, `research_unit`,
`scope`, `status`, and `deadline` are not recognized. Only canonical keys
receive typed semantics; all other source remains custom and targeted edits
never normalize it.

### Shared presentation and settings rules

Group order is Analysis **Source → Publication → Access & Identifiers →
Research → Other Properties → Tags**, Topic **Topic Description → Research →
Other Properties → Tags**, and Work **Work Description → Research → Other
Properties → Tags**. One catalog owns membership. **Other Properties** contains
all safe custom projections together without granting type or creation
semantics. Complete Properties and About use the same order and distinguish
groups through whitespace, while retaining group names for assistive technology
instead of visible repeated headings. About shows only groups with nonempty
selected values. Tags are neutral content capsules.

`settings.json` schema, exact seed, About profile, and Analysis Agent
requirements share one exact-byte revision and one atomic save. Restore About
defaults never changes seed; clearing seed never changes profiles or
requirements. Seeds contain delimiter-free YAML mapping source, normalize only
configuration newlines to LF, require a terminating LF, and preserve comments, order,
quoting, scalar style, and meaningful blank lines. They never contain title;
Analysis seeds also never contain type. Invalid, duplicate, reserved,
unsupported, larger than 64 KiB in UTF-8, or required-field-colliding source
cannot be saved.

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
