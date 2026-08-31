# Specification: Metadata and Critique

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Appendices A–B.

## Appendix A. Metadata catalogs and settings

This appendix owns the authored-YAML allowlist, built-in managed catalogs, and
Triptych-extensible field definitions. Authored source, managed Metadata, app
facts, and integrations remain separate authorities.

### Shared authored YAML

| YAML key | Shape | Rule |
| --- | --- | --- |
| `summary` | Multiline text | Optional researcher-authored navigation description. |
| `keywords` | Text list | Optional researcher-authored retrieval terms. |

Managed creation writes `summary: null` and `keywords: []`; both count as absent
until populated. They are edited in Source. Every other YAML key is preserved
exactly as custom source without canonical or managed-field semantics.

### Analyses

All built-in Analysis fields are optional researcher-owned managed values.

| Group | Keys and shapes |
| --- | --- |
| Source | choice `type`; text `title`, `short_title`, `original_title`, `reviewed_title`, `genre`, `medium`, `version`, `language`; CreatorList `authors`, `editors`, `translators`, `collection_editors`, `container_authors`, `original_authors`, `reviewed_authors` |
| Publication dates | `publication_date`, `original_publication_date`, `event_date` |
| Publication text | `publication_status`, `container_title`, `container_title_short`, `series_title`, `series_number`, `volume`, `volume_title`, `issue`, `pages`, `chapter_number`, `edition`, `number_of_volumes` |
| Publication agents/events | `publisher`, `publisher_place`, `original_publisher`, `original_publisher_place`, `institution`, `report_number`, `event_title`, `event_place` |
| Access & Identifiers | date text `accessed_date`; text `doi`, `isbn`, `issn`, `url`, `pmid`, `pmcid`, `arxiv_id`, `archive`, `archive_collection`, `archive_location`, `archive_place`, `call_number` |

A CreatorList is a nonempty ordered list of either person mappings with required
`family` and optional `given`, `suffix`, `non_dropping_particle`, and
`dropping_particle`, or a literal mapping with only nonempty `literal`.
Scholium does not split, invert, transliterate, or normalize names.

`type` is one of: `journal_article`, `book`, `chapter`,
`encyclopedia_entry`, `thesis`, `manuscript`, `report`, `preprint`,
`conference_paper`, `presentation`, `webpage`, `review`, `dataset`,
`software`, `archival_item`, `correspondence`, `audiovisual`, or `other`.

Source-type profiles own applicable fields and recommended discovery order.
`other` permits the complete catalog. Agent-preferred fields must be applicable
and shape-known but remain optional. The required `source_type` creation input
only routes creation and derives managed `type`.

Default About shows managed `type`, `authors`, and `publication_date`, then
authored `summary` and `keywords`. Managed `title` resolves Analysis identity
but is not repeated in About.

### Topics

| Authority | Key | Shape | Default group |
| --- | --- | --- | --- |
| Managed Metadata | `aliases` | Text list | Topic Description |
| Authored YAML | `summary` | Multiline text | Authored YAML |
| Authored YAML | `keywords` | Text list | Authored YAML |

Topic identity is first H1, then filename. Similar-looking custom YAML keys have
no canonical meaning.

### Works

| Authority | Key | Shape | Default group |
| --- | --- | --- | --- |
| Managed Metadata | `work_type` | `paper`, `chapter`, `book`, `talk`, `review`, `teaching`, or `other` | Work Description |
| Managed Metadata | `coauthors` | Text list | Work Description |
| Authored YAML | `summary` | Multiline text | Authored YAML |
| Authored YAML | `keywords` | Text list | Authored YAML |

Work identity is first H1, then filename. Similar-looking custom YAML keys,
including status or deadline fields, have no canonical meaning.

### Shared presentation and settings rules

Group order is:

- Analysis: Source, Publication, Access & Identifiers, Custom Metadata, Authored
  YAML;
- Topic: Topic Description, Custom Metadata, Authored YAML;
- Work: Work Description, Custom Metadata, Authored YAML.

Metadata and About preserve group semantics for accessibility but use whitespace
instead of repeated visible headings. About shows selected nonempty values;
keywords are neutral content capsules.

Defined, applicable, recommended, Agent-preferred, present, and About-visible
are independent. Definitions and preferences never create or require a Note
value.

One revision-checked `settings.json` stores managed-field definitions, About
profiles, and Analysis Agent preferences. A custom field uses a lowercase
snake-case key and text, multiline text, text list, number, boolean, source-safe
date, or controlled-choice shape. It cannot shadow built-in or authored YAML.
Key, value kind, and order are immutable; label/description may change and
choices may only be appended.

Archive/Restore preserves stored values and Search/editing validation while
removing the field from new-value, About-selection, and Agent-preference
choices. Restore About defaults changes no definitions or Agent preferences.
The fixed authored-YAML scaffold is creation policy, not editable Settings.

## Appendix B. Bundled Critique Method requirements

The bundled Critique Skill inspects the bounded Work plus applicable Analyses
and Topics. It distinguishes what those Notes report, support, dispute, or leave
uncertain from the Agent's own reconstruction and evaluation. Neutral links and
transitive paths are never evidence.

Whole-Work Critique addresses material strengths, weaknesses, method fit,
source/perspective coverage, conceptual and argumentative command, sustained
contribution, defensibility, omissions, implications, objections, alternatives,
and revision priorities as warranted by genre, scope, and inspected evidence.
It is not a score or universal method.

Passage Critique identifies the exact target, issue, significance, research
basis, and recommendation without generalizing to the complete Work. Every
Critique records material access limits and uncertainty but does not inventory
reading. It never certifies novelty, publishability, doctoral level, field
completeness, or researcher competence.

**Traced**, **Untraced**, **Disputed**, and **Beyond Sources** remain attributed
Agent judgments, not Scholium statuses. Critique never modifies the Work; a
source change requires current Write authority.

The Critique registration identifies one researcher-owned Skill folder.
Scholium does not read, edit, validate, snapshot, or restore its contents. This
appendix specifies outcomes without duplicating that Skill's method prose.
