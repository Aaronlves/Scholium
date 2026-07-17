# Scholium Property Profiles

**Status:** Target product property vocabulary for the default Triptych
**Applies to:** Analyses, Topics, and Works
**Source policy:** Existing and custom YAML remains authoritative and losslessly preserved. These profiles define Scholium's recommended researcher-facing fields; they do not migrate notes, erase other properties, or change current runtime behavior by themselves.

## Principles

- Use a property only when it supports identification, retrieval, workflow, or an explicit research decision.
- Make a note's epistemic scope explicit through a minimal **Research Unit** when that scope would otherwise be ambiguous.
- Keep source condition separate from analysis progress, local project use, and an optional scoped assessment of importance within a real debate.
- Treat note development, work production, Human Review, and philosophical settlement as different states.
- Keep machine identifiers, schema markers, citation or Zotero keys, fingerprints, and provenance stores out of the ordinary property summary.
- Do not require YAML in Topics. A title, headings, folders, links, citations, and prose may be sufficient.
- Keep every governed custom schema on its own contract. Works properties do not substitute for settlement, evidence, privacy, or prose-permission controls.
- Preserve existing YAML without treating every preserved field as a Scholium requirement.

## App-owned time and history

Creation and modification times are app-owned History facts, not properties that a researcher or agent must fill.

- Scholium records and presents creation and modification information through app-owned state and Note History.
- Agents never create, infer, or maintain `created`, `updated`, `modified`, `created_at`, `updated_at`, `last_modified_at`, or equivalent timestamp properties.
- Existing timestamp keys remain exact source and are preserved for compatibility. Their presence does not make them part of the target profile, and their absence is not a validation error.
- The default profiles do not expose these keys, and repository saves do not inject or refresh them. App-owned version History supplies new save timestamps while existing vault bytes remain untouched.

## Research Unit

Research Unit is a minimal declaration of the domain within which a note's claims apply. It is stored under `research_unit` in YAML and presented in the interface as **Research Status**. It is not a new note type, task, progress tracker, or project object.

The complete default shape is:

```yaml
research_unit:
  scope: "Introduction and Chapters 1–4"
  limitations:
    - "Chapters 5–8 and the appendix have not been analyzed."
```

Only two nested fields are defined:

| Field | Shape | Rule |
| --- | --- | --- |
| `scope` | non-empty text | Required whenever `research_unit` is present. State the exact source segment, conceptual domain, or Work question to which the note applies. |
| `limitations` | list of non-empty text | Optional. Record only exclusions, incomplete access, unfinished passes, or other boundaries that materially restrict what the note may claim. |

Do not add nested `type`, `target`, `coverage`, `coverage_percentage`, `completeness`, `confidence`, `reading_protocol`, pass booleans, timestamps, backlinks, or relation counts. The note's vault role supplies the type; Analysis identity fields identify its source; links and Connections identify related notes; the app derives reverse relations, counts, and history.

Research Unit has role-specific meaning:

| Note role | Meaning of `scope` |
| --- | --- |
| **Analysis** | The exact source material actually represented by the analysis, such as an entire paper, one chapter, a page range, or cumulative portions of a monograph. |
| **Topic** | The conceptual, problematic, or debate domain within which the synthesis applies. |
| **Work** | The project question, argumentative domain, or bounded part of the Work to which its present claims apply. |

Dialogue does not receive YAML frontmatter. Its app-owned selected-note, selection, Comment, and scope records provide the Dialogue Research Unit. Scholium may present that target as Research Status without creating or modifying a Markdown property.

### Requiredness and migration

- A new durable **Analysis** may use **Not Yet**. In that case Scholium writes no
  `research_unit` mapping and no sentinel value. Editing, Comments, Dialogue,
  Develop, and a Review draft remain available.
- **Complete Review** requires a declared Research Unit. The Review panel
  explains the gate and offers **Declare Research Status…** without treating the
  absent mapping as malformed.
- Any Analysis without `research_unit` remains valid and is presented as **Not
  Yet**. Existing notes receive no migration or automatic YAML rewrite.
- A **Topic** or **Work** may declare a Research Unit when a durable boundary adds information not already clear from its title, prose, and links. Scholium does not add YAML merely to create this field.
- An agent may add or change `research_unit` only when the exact write set authorizes that property change. Missing scope is reported separately when permission is absent.
- Scholium performs no automatic bulk migration and does not infer scope from folder names, keywords, link proximity, or the amount of text in a note.

### Long-source continuity

One source normally has one continuously maintained Analysis file, including a long monograph.

- Each work session declares a bounded analysis unit and completes the Orientation, Analytical, and Review passes over that unit.
- The existing source-level Analysis is updated in place; its `research_unit.scope` expands only to material actually inspected and represented in the file.
- `limitations` records unread or excluded material and any incomplete pass that constrains current claims.
- Adding a partially analyzed unit returns the Analysis to `draft` when a status change is authorized. `complete` means complete for the currently declared Research Unit, not necessarily for the physical source as a whole.
- Use `scope: "Entire source"` only after the complete source has received the required source-wide analysis and review. A collection of chapter notes or partial passes does not silently become a whole-book analysis.
- Do not create one Analysis note per chapter by default. Create a separate note only when the researcher requests it or the segment needs an independently citable scholarly identity.

## Vault-wide presentation

Scholium starts with one profile for each Triptych vault. In **Settings → Properties**, the researcher may set visible fields and their order, the human-editable allowlist, and whether the Properties disclosure starts open. Each configuration applies to the complete Analyses, Topics, or Works vault; Scholium provides no folder-level or note-level override.

The configuration changes only Scholium's projection and targeted editing affordances. It never sorts, migrates, removes, or otherwise rewrites frontmatter. Exact YAML remains available in Source mode.

The structured interface presents `research_unit` as **Research Status**, with **Scope** first and **Limitations** only when non-empty. Existing top-level `status` may appear in the same visual group but remains a separate property with role-specific semantics.

## Shared Triptych keys

Analyses, Topics, and Works use one compact YAML vocabulary wherever the same idea recurs: `title`, `tags`, `status`, and `research_unit`. Analyses and Works also share `authors`. Analyses may use `type` for the form of the analyzed source; Works may use `kind` for the form of the researcher's output.

A shared key names the same broad kind of fact, while its allowed values and precise meaning remain scoped to the vault role. For example, `status` tracks analysis progress in Analyses, note development in Topics, and production state in Works. It never records creation or modification time.

## Analyses

Analyses describe a source-facing reconstruction or assessment. Bibliographic identity is required for a new durable Analysis; epistemic scope may be declared at creation or remain **Not Yet** until Complete Review.

| Group | Property | YAML key | Shape | Purpose |
| --- | --- | --- | --- | --- |
| About | Title | `title` | text, required | Title of the analyzed source. |
| About | Authors | `authors` | list, required | Source authors. |
| About | Year | `year` | number, required | Publication year. |
| About | Type | `type` | controlled text | Publication form, not philosophical role. |
| About | Tags | `tags` | list | Lightweight retrieval terms. |
| Research Status | Research Unit | `research_unit` | optional mapping at creation; required before Complete Review | Exact represented source scope plus optional material limitations. **Not Yet** writes no mapping or sentinel. |
| Source | Access | `access` | controlled text | How much source material was available. |
| Source | Text Reliability | `text_reliability` | controlled text | Reliability of the consulted text. |
| Source | Locators | `locators` | controlled text | Whether citations have stable, checkable locations. |
| Progress | Status | `status` | controlled text | `draft`, `complete`, or `reviewed`; judged against the declared Research Unit. |
| Assessment | Debate Importance | `debate_importance` | whole number 0–10 | Optional importance within the separately named debate scope; not project relevance, quality, truth, prestige, or citation count. |
| Assessment | Debate Scope | `debate_importance_scope` | text | Required whenever Debate Importance is present; names the debate, domain, tradition, period, or reception context assessed. |

Folders, tags, links, citations, and the report body carry topic placement, source use, and follow-up context without duplicating them as properties. Project Relevance, when requested, belongs in the Analysis body because relevance is contextual and may differ across Works; it is not a universal Analysis property. Existing `relevance` YAML remains preserved as custom or legacy data.

Debate Importance exists for prioritizing a large Analyses vault. It is optional, has no pass grade, and must be omitted when adequate comparative context is unavailable. Its report rationale identifies why the source is peripheral, materially important, substantial, major, or constitutive within the stated scope. Citation count, reputation, the source's self-description, or usefulness to the researcher's current project cannot establish the rating by themselves. `debate_importance` and `debate_importance_scope` are added, changed, or removed together.

Ratings are comparable only inside one exact Debate Scope. The Library exposes numeric high-to-low ordering only after its metadata filter selects one `debate_importance_scope`; unrated matching Analyses sort after rated ones. A bounded Research Synthesis may periodically recalibrate a large same-scope corpus with common anchors. Reviewer remains responsible for evaluating philosophical work and is not repurposed as an importance assessor.

Nested audit data and machine linkage may remain in exact YAML. Scholium displays such structures read-only unless a separately approved targeted editor owns them.

## Topics

Topics are evolving concept, problem, debate, or synthesis notes. YAML is optional, and the profile is intentionally small.

| Group | Property | YAML key | Shape | Purpose |
| --- | --- | --- | --- | --- |
| About | Title | `title` | text | Optional when filename and H1 already identify the topic. |
| About | Aliases | `aliases` | list | Alternative names used in Search and links. |
| About | Tags | `tags` | list | Lightweight retrieval terms. |
| Research Status | Research Unit | `research_unit` | mapping | Optional conceptual or debate boundary plus material limitations. |
| Progress | Status | `status` | controlled text | Note development: `seed`, `developing`, or `maintained`; not philosophical settlement. |

Source support belongs in citations, footnotes, callouts, and source-anchored links. A Topic property must not claim that cited material supports the note merely because a link exists.

## Works

Works are researcher-authored outputs such as articles, chapters, books, talks, reviews, and teaching materials.

| Group | Property | YAML key | Shape | Purpose |
| --- | --- | --- | --- | --- |
| About | Title | `title` | text, required | Title of the Work. |
| About | Authors | `authors` | list | Co-authors when applicable. |
| About | Kind | `kind` | controlled text | Form of the authored Work, such as paper, chapter, book, talk, review, or teaching material. |
| About | Tags | `tags` | list | Lightweight retrieval terms. |
| Research Status | Research Unit | `research_unit` | mapping | Optional project question, argumentative domain, or bounded Work scope plus material limitations. |
| Progress | Status | `status` | controlled text | `planning`, `drafting`, `revising`, `review`, `ready`, `submitted`, `published`, or `archived`. |
| Use | Venue | `venue` | text | Intended or actual journal, publisher, course, or event. |
| Use | Deadline | `deadline` | date | Relevant delivery or submission date. |

Works status records production state only. It does not encode argumentative quality, evidential sufficiency, acceptance probability, or a project-governance decision.

Works folders carry researcher-defined grouping. Scholium does not add a `project` property, register project membership, or infer a project from this profile.

## Compatibility

Legacy keys remain readable and stay untouched during ordinary saves. Existing timestamp and relevance keys remain preserved but are not part of the target default profile. When a researcher deliberately edits one recognized non-time property, Scholium writes that property under its canonical Triptych key and removes only the corresponding legacy alias; it does not bulk-migrate the note.

Other non-machine fields remain visible as custom properties, and exact YAML stays available in Source mode. Internal and CLI role identifiers remain stable for registry and automation compatibility even when the interface says Analyses, Topics, and Works.
