# Specification: Property Profiles and Critique

Part of the canonical document set rooted at [SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md).
This chapter owns Appendices A–B: default property profiles and bundled Critique requirements; sibling chapters do not restate it.

## Appendix A. Default property profiles

Existing/custom YAML remains authoritative and losslessly preserved. Canonical
vocabulary defines recognized meaning; About defines the default read-only
projection; creation requirements are empty for every role. Profiles never
inject absent YAML, erase unknown source, or turn visibility into editability.
App-owned time and provenance remain outside frontmatter. Research Unit follows
the role-aware constraints in §5.2.

### Analyses

| YAML | Ownership | Default About | Rule |
| --- | --- | --- | --- |
| `title` | Researcher | No | Source identity; resolver fallback is H1, then filename. |
| `research_unit` | Researcher | Completion, then every Limitation | Optional `completion` and/or `limitations`. |
| `authors` | Researcher | Yes | Author list. |
| `year` | Researcher | Yes | Publication year. |
| `type` | Researcher | Yes | Publication form. |
| `access` | Researcher | Combined Source Basis | Extent of consulted material. |
| `text_reliability` | Researcher | Combined Source Basis | Reliability of consulted text. |
| `locators` | Researcher | Combined Source Basis | Citation stability/checkability. |
| `tags` | Researcher | No | Retrieval terms. |
| `summary` | Researcher / authorized Agent | Yes | Optional short navigation declaration; one current YAML owner, actual writer retained. |
| `debate_importance` | Researcher | No | Optional whole number 0–10. |
| `debate_importance_scope` | Researcher | No | Must appear with Debate Importance. |
| `zotero_item_key` | Protected machine | No | Exact task-context identity; not ordinarily editable. |

Debate Importance follows 5.2 and never means project relevance, quality,
truth, prestige, or citation count. Relevance keys remain custom source.

### Topics

Topic YAML is optional.

| YAML | Ownership | Default About | Rule |
| --- | --- | --- | --- |
| `research_unit` | Researcher | Scope, then every Limitation | Optional `scope` and/or `limitations`. |
| `aliases` | Researcher | Yes | Search and link alternatives. |
| `tags` | Researcher | No | Retrieval terms. |
| `summary` | Researcher / authorized Agent | Yes | Optional short navigation declaration; one current YAML owner, actual writer retained. |

Topic identity is first H1, then filename. YAML `title` is not recognized.

### Works

| YAML | Ownership | Default About | Rule |
| --- | --- | --- | --- |
| `research_unit` | Researcher | Research Scope, then every Limitation | Optional `scope` and/or `limitations`. |
| `kind` | Researcher | Yes | Paper, chapter, book, talk, review, teaching material, etc. |
| `authors` | Researcher | Yes | Co-authors when relevant. |
| `venue` | Researcher | Yes | Intended or actual journal, publisher, course, or event. |
| `tags` | Researcher | No | Retrieval terms. |
| `summary` | Researcher / authorized Agent | Yes | Optional short navigation declaration; one current YAML owner, actual writer retained. |

Work identity is first H1, then filename. YAML `title`, `status`, and `deadline`
are not recognized. Only canonical keys receive typed semantics; all other
source remains custom and targeted edits never normalize it.

## Appendix B. Bundled Critique Method requirements

The bundled Critique Skill must inspect the bounded Work context and applicable
Analyses and Topics; distinguish what those notes report, support, dispute, or
leave uncertain from the agent's own reconstruction or evaluation; and treat
neither neutral links nor transitive paths as evidence.

For the whole Work it addresses material strengths, weaknesses, source
coverage, omissions, objections, alternatives, and priorities. For a selected
passage it identifies the exact target, issue, significance, research basis,
and recommendation. It records the Materials actually consulted, access limits,
and uncertainty. Any Traced, Untraced, Disputed, or Beyond Sources label remains
an attributed agent judgment, never a Scholium status.

Critique never modifies the target Work. A recommended source change requires
current Write authority. The Critique registration's editable primary Markdown
owns the active method; the app-bundled default is read only and used only for
explicit restoration. This specification states requirements without
duplicating the Skill's complete prose.
