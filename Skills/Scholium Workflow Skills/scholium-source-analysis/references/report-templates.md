# Source Analysis Report Templates

Use these templates when a durable report is requested or project rules require one.

For a new durable Analysis, declare its Research Unit in frontmatter:

```yaml
research_unit:
  scope: "Exact source material represented by this report"
  limitations:
    - "A material boundary on what the report may claim."
```

`scope` is required. Omit `limitations` when none remains; do not add other nested fields. Creation and modification time are app-owned History data and must not appear as agent-filled template fields.

When adequate contextual evidence supports a Debate Importance assessment, the optional properties are separate from Research Unit. Scholium may sort them only after the researcher filters the Library to one Debate Scope:

```yaml
debate_importance: 7
debate_importance_scope: "The contemporary debate over [named question]"
```

Both fields are required together. Omit both when the debate scope or comparative evidence is insufficient. The report body must give the rationale; the number is not a quality, truth, prestige, citation-count, or project-relevance score. Ratings under different scopes must not be compared as one ranking.

For a long source, update one source-level Analysis by default. Revise the report into one coherent current account and expand its Research Unit only after the new session unit completes all three passes. Do not append disconnected chapter reports or create a chapter note merely to record reading progress. Preserve earlier warranted analysis; History, rather than timestamp frontmatter or a session log, records revisions.

## Thorough Report

```markdown
# Author (Year): Short Title

## 1. Metadata

- Reference:
- Source file or citation:
- DOI:
- Venue:
- Version status:
- Source type:
- Source function or genre:
- Page range:
- Selectable-text reliability:
- Pagination reliability:
- Reading status:
- Reading-depth rationale:
- Materials checked:
- Materials unavailable:
- Locator policy:
- Additional references used:

## 2. Research Scope

- Session analysis unit:
- Durable Research Unit after this update:
- Orientation pass: complete | incomplete
- Analytical pass: complete | incomplete
- Review pass: complete | incomplete
- Material limitations:

Do not describe the entire source as analyzed unless the Research Unit is the entire source and all three passes were source-wide.

## 3. Project Relevance

- Rating: 0–10, only when project context exists.
- Pass threshold: 5/10.
- Rationale:
- Primary domain:
- Secondary domains:
- Recommended role:

Omit this section when no project context exists unless the user requests a relevance assessment.

A passing rating means that the analysis establishes at least one concrete, warranted use in the stated project. It does not rate the source's truth, philosophical quality, prestige, reliability, or overall importance. Explain the project relation; do not infer it from keyword overlap.

## 4. Debate Importance

- Rating: 0–10, only when a named debate scope and adequate contextual evidence exist.
- Assessed debate, domain, tradition, period, or reception context:
- Evidence-based rationale:
- Importance type: background | representative | objection | conceptual resource | major intervention | agenda-setting | canonical | other
- Assessment limit:

There is no pass grade. Omit the rating rather than infer importance from citations, prestige, familiarity, the author's self-positioning, or project usefulness.

Omit this entire section unless the researcher requested prioritization or the active Analysis workflow explicitly calls for the property. If requested but not warranted, retain the section only to explain `Not assessed`.

For a large Analyses corpus, ratings made at different times may require a bounded Research Synthesis to recalibrate them against one common debate map. Reviewer evaluates philosophical work; it does not independently determine a source's importance in a field.

## 5. Debate-Framing Profile

Use page or stable locators for source-specific claims.

- Problem setup:
- Live question as the author frames it:
- Rival philosophers, views, or camps and their roles:
- Standards used to evaluate rivals:
- Claimed gap or unresolved pressure:
- Contribution type: solution, correction, synthesis, reframing, extension, restriction, deflation, methodological shift, or other.
- Author's historical narrative:
- Independently verified or still-unverified history:

## 6. Concepts, Claims, and Argumentative or Interpretive Structure

- Central concepts and distinctions:
- Central question:
- Thesis, governing claim, or purpose:
- Dialectical target:
- Author's reports of other sources:
- Source-supported reconstruction:
- Analyst-supplied charitable repair, if any:

For each central analytical unit, use only the fields appropriate to its philosophical function.

### Unit 1: [Argument / Interpretive Move / Conceptual Intervention / Case / Phenomenological Description / Formal Result / Normative Argument]

- Unit type and philosophical function:
- Claim, conclusion, interpretation, distinction, description, or result:
- Grounds: premises, passages, cases, descriptions, derivation, or empirical findings:
- Inferential, interpretive, conceptual, explanatory, formal, or normative link:
- Scope, modality, and claimed force:
- Hidden assumptions and burden of proof:
- Support type and exact support:
- Objection or alternative, its provenance, and exact target:
- Author's reply and reply type:
- Reply cost, concession, burden shift, and residual pressure:
- Analyst-generated objection or repair, if any:
- Logical, textual, conceptual, phenomenological, formal, normative, or evidential check as applicable:
- Page or stable-locator support:

## 7. Project and Knowledge-Base Use

Explain how the source relates to previous sources, concepts, arguments, debates, notes, or project questions. Classify source role only when established by the analysis. State what to use the source for, what not to use it for, and any approval-gated handoff candidates. Separate source interpretation from project use.

Omit this section in `analysis-only` mode or when no project context exists.

## 8. Bibliography Screening

Include only verified useful sources and clearly labeled follow-up leads. An unread bibliography item is a lead, not evidence for a claim or relation.

## 9. Residual Problems and Open Questions

List unresolved objections, possible misreadings, unsupported premises, verification gaps, and follow-up research tasks.
```

## Concise Report

Use when the user asks for a quick report or when the requested task, available material, genre, complexity, and interpretive risk support concise treatment. Project relevance does not determine report depth.

```markdown
# Author (Year): Short Title

## Metadata

- Reference:
- Source status:
- Reading status:

## Research Scope

- Session analysis unit:
- Durable Research Unit after this update:
- Three-pass state:
- Material limitations:

Do not collapse partial-source completion into a whole-source claim.

## Project Relevance

- Rating (0–10), only when project context exists:
- Pass threshold: 5/10.
- Reason:

Omit this section in `analysis-only` mode or when no project context exists.

A passing rating requires at least one concrete, warranted project use. It is not a rating of source quality, truth, prestige, or reliability.

## Debate Importance

- Rating (0–10), only when contextually warranted:
- Assessed debate or domain:
- Rationale and limitation:

Omit this entire section unless requested or required by the active Analysis workflow. When requested but comparative debate context is insufficient, state `Not assessed` without a number. It has no pass grade and is not project relevance or source quality.

## Gist and Evidential Layers

State the central question or purpose, thesis or governing claim, method, and compact debate-framing note in a few paragraphs. Label author-explicit material, source-supported reconstruction, analyst-supplied charitable repair, and analyst evaluation separately whenever they occur. Do not fold a repair into the reconstruction.

## Project and Knowledge-Base Use

Explain the source's concrete project role, limits, and any use that remains only a candidate.

Omit this section in `analysis-only` mode or when no project context exists.

## References Worth Following

List only clearly relevant leads.

## Open Questions

State uncertainties and verification needs.

## Use Candidates

Usually minimal or none.

Omit this section in `analysis-only` mode or when no project context exists.
```

## Provisional Report

Use when only an abstract, excerpt, unreliable PDF, or partial source is available.

```markdown
# Provisional Analysis: Author (Year): Short Title

## Metadata

- Available material:
- Missing material:
- Source-access limitation:

## Research Scope

- Available session analysis unit:
- Durable Research Unit represented:
- Passes completed over available material:
- Material limitations:

## What Can Responsibly Be Said

State only claims supported by the available material.

## What Cannot Yet Be Claimed

Identify arguments, page-specific claims, quotations, or source roles that require full-text access.

## Likely Question, Thesis, or Topic

Mark as provisional.

## Possible Relevance

When project context exists, mark as provisional. Omit this section in `analysis-only` mode.

## Debate Importance

Include only when requested. Normally state `not assessed from partial material` unless independent checked debate context is sufficient. Do not infer a number from the excerpt, abstract, citation count, or source reputation alone.

## Verification Needed

List exact next checks.

## Use Candidates

When project context exists, keep these at candidate level. Omit this section in `analysis-only` mode. Do not update project files from a provisional analysis unless the user explicitly asks.
```
