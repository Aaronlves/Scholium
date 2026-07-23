# Properties and Research Unit

Use the profile assigned by Scholium to the registered vault role. Existing
and custom YAML remains authoritative. Never normalize, reorder, migrate, or
complete frontmatter merely because a canonical or default About field exists.

## 1. Keep three contracts separate

- **Canonical vocabulary** defines the keys Scholium understands, their types,
  constraints, ownership, and editability.
- **Default About** defines only which non-empty facts the Inspector normally
  presents and in what order.
- **Creation requirements** are empty for Analysis, Topic, and Work.

No field is required merely because it is useful or appears in About. Do not
fill every possible property. Fill only values genuinely needed by the task
and warranted by verified metadata, explicit researcher information, or the
authorized workflow result.

Include each researcher-owned key in the exact write set before changing it.
Preserve unknown, custom, nested, and protected-machine properties unless the
exact task separately authorizes them. Creation and modification time are
app-owned history; preserve any existing timestamp-like YAML as custom source.

`status`, Work `deadline`, and Topic/Work YAML `title` have no Scholium
semantics. Do not create, update, query, or recommend them. Unknown occurrences
remain untouched source rather than compatibility properties.

## 2. Role-aware Research Unit

Research Unit states a durable research boundary. It is not a note type,
workflow status, adequacy judgment, relation graph, or progress gate.

### Analysis

Analysis accepts `completion` and/or `limitations`:

```yaml
research_unit:
  completion: "6/11"
  limitations:
    - "Only the English translation was consulted."
```

Completion is `complete`, `incomplete`, or `completed/total`, where total is
positive and `0 <= completed <= total`. A ratio records how many selected
material units are represented. It does not identify the units, certify
adequacy, claim that a reading pass is complete, or create a chapter ledger.
An independently analyzed article in an edited collection may use the binary
form. Do not infer the form or total from Zotero type, children, or page count.

Limitations state independent material claim boundaries. Do not manufacture a
Limitation merely by paraphrasing an incomplete ratio.

### Topic and Work

Topic and Work accept `scope` and/or `limitations`:

```yaml
research_unit:
  scope: "The fittingness objection and its practical target"
  limitations:
    - "Historical variants are outside this note."
```

For Work, `scope` is the Research Scope: the research question, argumentative
target, and boundary. Write it only from the researcher's project information
or as the warranted result of an explicitly authorized Write.

For every role, an empty mapping, unknown member, wrong type, or member from a
different role is invalid. When changing one member, preserve every other
member byte-for-byte. Remove the complete mapping only when no valid member
remains. Do not infer Scope from a folder, filename, keyword, tag, link, nearby
note, prose length, or prior task.

## 3. Canonical role profiles

### Analysis

Researcher-owned keys are `title`, `authors`, `year`, `type`, `tags`,
`research_unit`, `access`, `text_reliability`, `locators`,
`debate_importance`, and `debate_importance_scope`.

Analysis title resolves from YAML `title`, then first H1, then filename. Do not
fabricate missing bibliographic identity. `debate_importance` is an optional
whole number 0–10 and must appear with non-empty
`debate_importance_scope`; authorize and change the pair together. It is not
project relevance, source quality, truth, prestige, or citation impact.

`zotero_item_key` is Analysis-only and protected-machine-owned. Do not expose
or fill it as ordinary profile completion. Change it only when the exact
machine/agent operation is authorized, the item identity is exact, and the
current note fingerprint is supplied. Zotero task metadata is not copied into
Markdown automatically.

### Topic

Researcher-owned keys are `aliases`, `tags`, and `research_unit`. Topic
identity is first H1, then filename. Do not add YAML solely to populate About.

### Work

Researcher-owned keys are `authors`, `kind`, `tags`, `research_unit`, and
`venue`. Work identity is first H1, then filename. Do not infer project
management state from prose, file location, age, Fidelity, or Research
Activity.

Put source support in prose, citations, footnotes, callouts, or source-anchored
links—not in Properties or Research Unit. A property, tag, or link alone is
never philosophical evidence.
