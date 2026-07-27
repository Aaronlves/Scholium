# Properties Decision Record

**Status:** Researcher-approved decision record; integrated by D-102<br>
**Recorded:** 2026-07-23<br>
**Canonical integration:** `SCHOLIUM_SPEC.md` D-102

This file records the approved direction for Scholium Properties. It is the
decision history behind `SCHOLIUM_SPEC.md` D-102, not a second product
specification. `IMPLEMENTATION_STATUS.md` alone records current conformance and
remaining acceptance.

## 1. Separate three contracts

Property profiles must no longer conflate three different questions:

1. **Canonical property vocabulary:** which fields Scholium understands,
   including their types, constraints, ownership, and editability.
2. **Default About fields:** which facts the Research Inspector shows by
   default and in what order.
3. **Creation requirements:** which missing facts, if any, block creation.

Visibility never determines semantic recognition. Semantic recognition never
implies human editability. Creation requirements never follow merely from a
field being useful or normally shown.

## 2. Creation requirements

Analysis, Topic, and Work have no required properties at creation. Missing
properties do not block creation, editing, Annotation, Comment, Discuss,
Write, Fidelity, Settle, Critique, Search, or recovery.

Properties use no asterisk or equivalent required-looking marker. Importance
is communicated by field order and concise explanatory text, not a second
requiredness model.

Cross-field validity remains distinct from creation requirements. If Debate
Importance is supplied, `debate_importance` and
`debate_importance_scope` must still appear together. If an optional Research
Unit is supplied, its role-specific shape must be valid.

## 3. Canonical vocabulary and default About fields

### 3.1 Analyses

Canonical human-editable vocabulary:

- `title`
- `authors`
- `year`
- `type`
- `tags`
- `research_unit`
- `access`
- `text_reliability`
- `locators`
- `debate_importance`
- `debate_importance_scope`

Canonical protected machine vocabulary:

- `zotero_item_key`

Default About order:

1. Completion, when declared
2. each non-empty Limitation
3. Authors
4. Year
5. Type
6. one compact Source Basis presentation composed from `access`,
   `text_reliability`, and `locators`

`title` remains durable Analysis metadata for source identity, Zotero
matching, agent context, and indexing, but it is not shown in About. Tags and
Debate Importance remain available without occupying the default About view.
`zotero_item_key` is protected, hidden from About, and unavailable to ordinary
structured editing.

### 3.2 Topics

Canonical vocabulary:

- `aliases`
- `tags`
- `research_unit`

Default About order:

1. Scope, when declared
2. each non-empty Limitation
3. Aliases

Topic title is document identity derived from H1, with filename fallback; it is
not a canonical YAML property. Tags remain available without occupying the
default About view.

### 3.3 Works

Canonical vocabulary:

- `authors`
- `kind`
- `tags`
- `research_unit`
- `venue`

Default About order:

1. Research Scope, when declared
2. each non-empty Limitation
3. Kind
4. Authors
5. Venue

Work title is document identity derived from H1, with filename fallback; it is
not a canonical YAML property. Research Scope states the Work's research
question, argumentative target, and boundary. The researcher may write it, or
an agent may write it only through an explicitly authorized Write. Agent
attribution remains app-owned Research Activity and Research Record data, not
additional YAML provenance.

## 4. Analysis Completion

Analysis does not use Research Unit `scope`. Its Research Unit contains a
lightweight Completion reminder and optional material Limitations.

For an Analysis whose target is a divisible long work:

```yaml
research_unit:
  completion: "6/11"
```

For an Analysis whose target is one independently analyzed item, including an
article in an edited collection:

```yaml
research_unit:
  completion: incomplete
```

The other binary value is `complete`.

Completion obeys these rules:

- The Simplified Chinese label is **完成度**.
- A ratio has the form `completed/total`, where `total` is positive and
  `0 <= completed <= total`.
- The completed count means that many selected units are represented in the
  Analysis. It does not certify adequacy, quality, Settle, Fidelity, or
  completeness of any philosophical reconstruction.
- Scholium does not record which units were represented, maintain a chapter
  ledger, infer a ratio from the body, or verify the researcher's count.
- The researcher or an explicitly authorized agent chooses binary or ratio
  form from the Analysis target. Zotero item type alone does not decide it.
- `incomplete` or a ratio below its total produces only a quiet, nonblocking
  reminder. Completion creates no Research Activity event, workflow gate,
  status model, Library order, or Search filter.

Completion and Limitations do not duplicate one another. Incompleteness alone
does not generate a Limitation such as “the remaining chapters have not been
analyzed.” Limitations record independent material claim boundaries, for
example that only one translation or an unreliable text was consulted.

Example:

```yaml
research_unit:
  completion: "6/11"
  limitations:
    - "Only the English translation was consulted."
```

Topic and Work Research Units retain `scope` plus optional `limitations`; they
do not use Analysis Completion.

## 5. Remove generic progress properties

Remove `status` from the canonical vocabulary, default About fields,
structured-editing allowlists, Library filters and ordering, Search syntax and
index columns, agent instructions, product skills, fixtures, and tests for all
three roles.

Research Activity records what occurred. Settle, Fidelity, Changed Since
Settled, Critique, and Critique Addressed express their own precise meanings.
They do not combine into another generic status. Scholium deliberately does
not retain the former Work lifecycle values such as `submitted`, `published`,
or `archived`. If a concrete publication workflow is approved later, it must
receive a specific contract rather than revive generic `status`.

Remove `deadline` from Work vocabulary, About, structured editing, and tests.
Scholium does not use a frontmatter deadline as project-management state.

## 6. Remove default disclosure state

Remove **Open Properties by Default** and the stored `isExpanded` property.
About is the stable compact projection; complete Properties is an explicit
editing destination. There is no vault-wide default disclosure state.

## 7. Clean cutover and source fidelity

Scholium has not entered production with the removed property contract. Do not
add compatibility decoders, migration branches, aliases, legacy UI, or legacy
tests for `status`, `deadline`, Topic/Work YAML `title`, required-property
markers, or `isExpanded`.

This clean cutover does not weaken the general exact-source rule. Unknown YAML
in researcher Markdown remains byte-preserved unless the researcher explicitly
edits that exact field. Such preservation is ordinary Markdown fidelity, not a
legacy semantic contract for removed properties.

## 8. Zotero metadata boundary

Scholium's built-in Zotero connection remains local and read-only even if a
future Zotero API supports writes. Zotero metadata is divided into three
layers.

### 8.1 Protected Analysis identity

`zotero_item_key` is an Analysis-only protected-machine property. Scholium
offers no **Create Analysis from Zotero**, matching, comparison, confirmation,
or metadata-overwrite workflow. A protected machine or authorized agent path
may write the key only through the current-fingerprint source-mutation
boundary. Ordinary Properties cannot display or edit it.

### 8.2 Task-scoped Research Action context

When an Analyze Action begins preparation and the exact
`zotero_item_key` is present, Scholium performs one exact local read and
automatically attaches the protected `scholium-zotero-integration` package.
The immutable task snapshot may contain:

- item key, item type, title;
- complete creator names and roles;
- date, year, language;
- container, volume, issue, pages, edition, series, publisher, and place;
- DOI, ISBN, ISSN, citation key, and URL; and
- abstract, tags, Collections, and Zotero modification time.

The snapshot is labelled **Zotero bibliographic metadata**. Abstract, tags,
and Collections remain metadata and are never paper content or philosophical
evidence. The same Research Action reuses its snapshot when resumed; every
new function reads Zotero again. There is no cross-task metadata cache.

Zotero unavailability, a missing item, or an invalid response produces one
nonblocking task warning. The agent continues from available sources and fills
only information genuinely needed by the task. An Analysis without a key and
every Topic or Work incur no Zotero read or warning.

No fetched metadata is copied into Markdown or displayed in Inspector.
Attachments, Zotero Notes, annotations, PDFs, and full text are never loaded
into automatic task context.

Zotero exposes item-type-specific fields and creator roles. Scholium should
preserve those distinctions rather than flatten every creator into Authors.
Relevant official references are:

- <https://www.zotero.org/support/dev/web_api/v3/local_api>
- <https://www.zotero.org/support/dev/web_api/v3/types_and_fields>
- <https://www.zotero.org/support/kb/item_types_and_fields>

### 8.3 Search and evidential boundary

The protected key and task metadata create no public Search field and do not
affect lexical relevance ranking.

Scholium never derives Analysis Completion totals from Zotero page counts,
item children, or item type.

## 9. Deliberately undecided implementation details

The following remain implementation choices and are not fixed by this record:

- the exact Properties controls for binary and ratio Completion;
- the visual treatment and location of the quiet incomplete reminder;
- the final typography and spacing tokens after human sample review; and
- the transport encoding used inside the immutable function packet.

These choices must preserve source authority, explicit edits, accessibility,
conflict handling, Zotero unavailability, and the distinctions in this record.

## 10. Canonical integration

`SCHOLIUM_SPEC.md` D-102 is the maintained target contract. Architecture,
implementation status, code, tests, fixtures, and product skills must remain
aligned with that canonical rule; this record preserves the rationale only.
