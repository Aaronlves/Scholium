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

Source editing and creation follow §§5.1–5.3. The allowlist applies to all
three vault roles; other keys remain exact custom source without managed semantics.

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
`other` permits the complete catalog. No field is automatically required or
maintained for an Agent. MCP creation does not accept the prior
`source_type`/managed bibliographic creation route.

Default Analysis About always shows managed `type`, `authors`, and
`publication_date` even when empty. Other-field visibility follows the shared
rule below. Managed `title` is the optional academic title; §5.2 owns Note identity.

### Topics

| Authority | Key | Shape | Default group |
| --- | --- | --- | --- |
| Managed Metadata | `aliases` | Text list | Topic Description |

Note identity for every role is defined in §5.2.

### Works

| Authority | Key | Shape | Default group |
| --- | --- | --- | --- |
| Managed Metadata | `work_type` | `paper`, `chapter`, `book`, `talk`, `review`, `teaching`, or `other` | Work Description |
| Managed Metadata | `coauthors` | Text list | Work Description |

Custom status or deadline fields create no product workflow semantics.

### Shared presentation and settings rules

Group order is:

- Analysis: Source, Publication, Access & Identifiers, Custom Metadata;
- Topic: Topic Description, Custom Metadata;
- Work: Work Description, Custom Metadata.

Catalog groups organize definitions and discovery. §§18.4–18.5 own About layout.
Configured managed fields are always shown; configuration controls their
order rather than hiding other stored values. Every other present managed value,
including an archived custom value, follows automatically. Empty unconfigured
fields become available by configuring About in Settings, not through an
Inspector Add Field command.
Authored YAML is excluded from these groups and has no dedicated field controls.

Defined, applicable, recommended, present, and About-always-shown remain
independent. A definition or always-shown choice creates no Note value;
presence alone makes an existing value visible.

One revision-checked `settings.json` stores managed-field definitions, About
profiles, and catalog presentation. A custom field uses a lowercase snake-case
key and text, multiline text, text list, number, boolean, source-safe date, or
controlled-choice shape. It cannot shadow built-in or authored YAML.
Key and value kind are immutable. Label, description, field order, and
controlled-choice order may change. Existing choices cannot be removed; new
choices may be inserted at any position.

Archive/Restore preserves stored values, About presentation, and
Search/editing validation while removing the field from new-value,
About-always-shown choices. Restore About defaults changes no definitions.

## Appendix B. Critique requirements

Critique has no fixed product operation, academic profile, result schema or
registered method. Optional headings such as Overall Assessment, Strengths,
Major Concerns, Source Support, Objections and Alternatives, Revision Priorities,
Specific Findings and Evidence Limits are writing aids, not required fields.

A Critique inspects the bounded Work plus applicable Analyses and Topics. It
distinguishes what those Notes report, support, dispute, or leave uncertain
from the Agent's own reconstruction and evaluation. Link occurrences and
transitive paths are never evidence.

Whole-Work Critique addresses material strengths, weaknesses, method fit,
source/perspective coverage, conceptual and argumentative command, sustained
contribution, defensibility, omissions, implications, objections, alternatives,
and revision priorities as warranted by genre, scope, and inspected evidence.
It is not a score or universal method.

Passage Critique identifies the exact target, issue, significance, research
basis, and recommendation without generalizing to the complete Work. Every
Critique records material access limits and uncertainty but does not inventory
reading. It never certifies research maturity, novelty, publishability, doctoral level, field
completeness, or researcher competence.

**Traced**, **Untraced**, **Disputed**, and **Beyond Sources** remain attributed
Agent judgments, not Scholium statuses. Critique never modifies the Work; a
source change requires current Write authority.

The researcher may select a host-owned Critique method Skill. Scholium does not
register, read, edit, validate, snapshot, or restore it. This appendix specifies
product outcomes without duplicating a method's prose.
