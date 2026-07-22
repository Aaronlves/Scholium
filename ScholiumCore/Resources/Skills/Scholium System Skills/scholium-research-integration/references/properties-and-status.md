# Properties, Research Unit, and Status

Use the profile assigned by Scholium to the registered vault role. Existing and custom YAML remains authoritative. Never normalize, reorder, migrate, or complete frontmatter merely because a default field exists.

## 1. General property rules

- Include each property key in the exact write set before changing it.
- Fill a value only from verified source metadata, explicit researcher information, or the active workflow's warranted result.
- Preserve unknown, custom, nested, and machine-managed properties unless the exact task targets them.
- Do not expose or rewrite machine identifiers, schema markers, fingerprints, Zotero linkage, provenance stores, or automatic history as ordinary properties.
- Do not add YAML to a Topic solely to display properties.
- Treat every governed custom schema as its own authority; do not substitute the default Works profile.

Creation and modification time are app-owned History data. Never add, infer, refresh, normalize, or maintain `created`, `updated`, `modified`, `created_at`, `updated_at`, `last_modified_at`, or an equivalent timestamp property. Preserve an existing timestamp key exactly as custom YAML unless a separately authorized migration owns that key. Its absence is never a metadata defect.

## 2. Research Unit

Research Unit declares the domain within which a note's claims apply. It is stored in YAML and presented in About as **Scope** and **Limitations**. It is not a note type, task, progress tracker, completeness score, or relation graph.

Use exactly this shape:

```yaml
research_unit:
  scope: "Introduction and Chapters 1–4"
  limitations:
    - "Chapters 5–8 and the appendix have not been analyzed."
```

- `scope` is required non-empty text whenever `research_unit` is present.
- `limitations` is an optional list of non-empty statements about exclusions, incomplete access, unfinished passes, or other boundaries that materially limit the note's claims.
- Do not add nested `type`, `target`, `coverage`, `coverage_percentage`, `completeness`, `confidence`, `reading_protocol`, pass booleans, timestamps, backlinks, or counts.
- The vault role supplies the note type. Identity properties and links supply source or project relations. Scholium derives reverse links, aggregate coverage, and History.

Apply the declaration by role:

- **Analysis** — exact source material represented by the Analysis;
- **Topic** — conceptual, problematic, or debate domain of the synthesis;
- **Work** — project question, argumentative domain, or bounded part of the Work.

Discuss has no YAML frontmatter. Its app-owned selected notes, selection, Comments, and request scope form its Research Unit.

### Requiredness and authorization

- A new durable Analysis may use **Not Yet**. In that case, write no
  `research_unit` mapping and no sentinel value; do not infer or add a
  declaration merely because the note is new.
- When the researcher chooses **Declare Now**, state the available segment and
  its limitations even when access is partial. The declaration records the
  claim boundary; it does not gate editing, Comments, Discuss, Develop, or Settle.
- Any Analysis without `research_unit` remains valid and is **Not Yet**, not malformed.
- Topic and Work Research Units are optional. Do not add YAML merely to create one.
- Add or revise `research_unit` only when that key is in the exact write set. Otherwise preserve it and report a scope problem separately.
- Never infer scope from a folder, filename, keyword, tag, link, nearby note, amount of prose, or previous agent task.

### Long-source continuity

Normally maintain one source-level Analysis for a long book.

1. Declare a bounded analysis unit for the current session.
2. Complete the Orientation, Analytical, and verification passes over that unit.
3. Update the existing Analysis in place.
4. Expand `research_unit.scope` only to material actually inspected and represented in the resulting file.
5. Use `limitations` for unread, excluded, unreliable, or incompletely checked material.

Do not create one Analysis per chapter by default. Create a separate Analysis only when the researcher requests it or the segment needs an independently durable scholarly identity. Use `scope: "Entire source"` only after source-wide analysis and verification. Completion of one session unit never licenses a whole-book claim.

## 3. Default property profiles

### Analyses

For a newly authorized durable Analysis using **Declare Now**, fill:

- `title` — verified analyzed-source title;
- `authors` — verified source authors;
- `year` — verified publication year;
- `research_unit` — exact represented source scope and optional limitations.

When creation uses **Not Yet**, omit `research_unit` entirely. Do not write an
empty mapping, placeholder scope, or sentinel value.

If required bibliographic identity cannot be verified, do not fabricate it: leave it unresolved under the active creation contract and report the gap. Use `type`, `tags`, `access`, `text_reliability`, `locators`, and `status` only when warranted. Scholium no longer generates, validates, or presents Project Relevance as an active property. Preserve existing `relevance` or `relevance_rating` YAML byte-for-byte as inactive custom data unless an explicit migration owns it.

The optional `debate_importance` property is a whole number from 0–10 and must appear together with non-empty `debate_importance_scope`. Add or change the pair only when both keys are authorized and the available checked source analysis and comparative context justify a judgment within the named debate, domain, tradition, period, or reception context. The rating has no pass grade. It is not project relevance, quality, truth, prestige, citation impact, or the source's self-assessment. Omit both fields when the evidence is insufficient and place the rationale or not-assessed reason in the report body.

### Topics

YAML is optional. When a note already uses the default profile or the researcher requests an authorized property edit, recognized fields are `title`, `aliases`, `tags`, `research_unit`, and `status`. Research Unit remains optional. Put source support in prose, citations, footnotes, callouts, or source-anchored links—not in a status, Research Unit, or link property.

### Works

For a newly authorized Work, fill `title`. Fill `authors`, `kind`, `tags`, `research_unit`, `status`, `venue`, or `deadline` only from the researcher's project information and only when authorized. Research Unit remains optional. Works status is production state, not philosophical quality, evidential sufficiency, or acceptance probability.

## 4. Status-change protocol

A content edit does not automatically justify a status transition. Change `status` only when:

1. the key is included in the exact write set;
2. the current and proposed values are known;
3. the proposed value belongs to the active vault profile;
4. the transition criteria below are satisfied;
5. the current task authorizes that metadata change.

Otherwise preserve the current status and report a recommended transition separately.

### Analyses

Judge Analysis status against its declared Research Unit, not automatically against the physical source as a whole.

| Status | Minimum criterion |
| --- | --- |
| `draft` | The declared scope is only partly analyzed, source access is inadequate for that scope, a required reading pass is unfinished, or substantive reconstruction and checking remain. |
| `complete` | The complete declared Research Unit is covered; all three passes are complete for it; access and reliability are stated; central concepts and reasoning are reconstructed; reliable locators are included where available; and material limitations remain explicit. This may still be a partial-source Analysis. |
| `reviewed` | A distinct review or content audit has examined the exact completed fingerprint and no unresolved material defect blocks this label. An audit pass does not imply that the source or interpretation is true. |

When newly added material is not yet fully analyzed, recommend or make an authorized return to `draft`. Never preserve `complete` by pretending the new material falls within a completed pass.

### Topics

| Status | Minimum criterion |
| --- | --- |
| `seed` | The note records an initial question, concept, or candidate relation and remains sparse or substantially open. |
| `developing` | The note contains substantive organized research but important conceptual, evidential, or dialectical work remains active. |
| `maintained` | The note has a stable recurring purpose and coherent current structure, and the researcher has authorized treating it as maintained. This is not philosophical settlement. |

### Works

| Status | Minimum criterion |
| --- | --- |
| `planning` | Scope, thesis, structure, or materials are being designed before a continuous draft exists. |
| `drafting` | Substantive prose is being produced and major sections remain incomplete. |
| `revising` | A substantial draft exists and is undergoing conceptual, argumentative, structural, or stylistic revision. |
| `review` | An exact version has intentionally entered researcher, supervisor, peer, or referee review. |
| `ready` | The researcher explicitly judges the intended version ready for its next external use. |
| `submitted` | The researcher confirms actual submission. |
| `published` | The researcher confirms actual publication. |
| `archived` | The researcher explicitly retires the Work from active production. |

Never infer `ready`, `submitted`, `published`, or `archived`. Do not infer any status from age, file location, an agent's confidence, a content-audit result alone, or the absence of visible problems.
