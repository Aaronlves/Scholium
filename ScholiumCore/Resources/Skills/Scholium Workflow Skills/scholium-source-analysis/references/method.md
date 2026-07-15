# Source-Analysis Method

## Contents

- [Access, session analysis unit, and durable Research Unit](#1-access-session-analysis-unit-and-durable-research-unit)
- [Three-pass reading protocol](#2-three-pass-reading-protocol)
- [Source project and genre](#3-source-project-and-genre)
- [Concepts and distinctions](#4-concepts-and-distinctions)
- [Arguments and interpretive moves](#5-arguments-and-interpretive-moves)
- [Genre-sensitive checks](#6-genre-sensitive-checks)
- [Objections and evaluation](#7-objections-and-evaluation)
- [Debate framing and research role](#8-debate-framing-and-research-role)
- [Output forms](#9-output-forms)

## 1. Access, session analysis unit, and durable Research Unit

Record verified bibliographic identity, source type, language and translation status, version, what was actually inspected, and whether access is complete, partial, excerpted, OCR-derived, or otherwise unreliable.

Distinguish two scopes:

- the **session analysis unit** is the bounded source material read through all three passes in the current task;
- the durable **Research Unit** is the cumulative source material actually represented by the saved source-level Analysis.

The session unit controls what the current task may analyze. The Research Unit controls what the durable file may claim. Neither may be inferred from the title, folder, existing report length, or the physical extent of the source.

Define the complete session analysis unit before reading:

- for a paper or chapter, use the whole paper or chapter unless the researcher explicitly bounds the task more narrowly;
- for a monograph, use the whole book only when whole-book analysis is actually requested and feasible; otherwise name the exact chapters or sections;
- for a source cluster, define and complete the unit for each source separately;
- for partial access, define the available excerpt or fragment as the unit and prohibit a full-source claim.

For a full-source analysis, each pass must inspect the entire session unit, including notes, appendices, figures, tables, examples, citations, or formal apparatus when they bear on the argument. Do not infer the whole work from its title, abstract, introduction, or conclusion.

For a long source, reuse one source-level Analysis by default. After the Review pass, integrate the current result into that file and expand its Research Unit only to material now represented in the whole report. Keep unread, excluded, unreliable, or incompletely reviewed material in `limitations`. Do not create chapter-by-chapter Analysis notes unless the researcher requests them or each segment needs an independently durable scholarly identity.

The durable YAML contract is intentionally minimal:

```yaml
research_unit:
  scope: "Introduction and Chapters 1–4"
  limitations:
    - "Chapters 5–8 and the appendix have not been analyzed."
```

Use only required `scope` and optional `limitations`. Do not store percentages, pass booleans, confidence, relations, or timestamps in Research Unit. Use `scope: "Entire source"` only after complete source-wide analysis and review. An Analysis may be `complete` for a declared partial-source Research Unit without being a complete analysis of the physical source.

Distinguish printed pagination from file pagination. Visually verify quotation, symbol, punctuation, and page-specific claims when extraction may be unreliable. Never fill missing metadata or locators from memory.

## 2. Three-pass reading protocol

Complete three distinct traversals of the session analysis unit in the current task. Search results, metadata inspection, text extraction, an outline scan, prior memory, or an earlier analysis do not count as a reading pass. Targeted verification may supplement a pass but cannot replace the complete traversal.

### Pass 1 — Orientation

Read the complete session analysis unit in source order. Establish:

- the question, pressure, or purpose;
- provisional thesis, governing interpretation, or contribution;
- section structure, argumentative movement, and turning points;
- source genre, method, intended scope, and the debate framing presented by the source;
- candidate load-bearing concepts, passages, arguments, objections, and replies;
- access gaps, extraction problems, and locator risks.

Produce a compact orientation map. Do not settle the final interpretation or begin the final report during this pass.

### Pass 2 — Analytical

Read the complete session analysis unit again. Use the orientation map as a guide, not as evidence. Reconstruct the source at the level appropriate to its genre:

- analyze load-bearing concepts and distinctions in their local use;
- reconstruct arguments, interpretations, descriptions, cases, formal moves, or normative bridges;
- separate author-explicit claims, reports of others, source-supported reconstruction, charitable repair, and evaluation;
- track objections, replies, concessions, alternatives, burdens, scope, modality, and residual pressure;
- attach reliable locators and record uncertainty where support remains incomplete.

Produce the analytical draft only after completing this second traversal.

### Pass 3 — Review

Read the complete session analysis unit a third time while testing the analytical draft against it. Review from the source outward rather than merely proofreading the draft. Check:

- whether any load-bearing claim lacks adequate source support;
- omitted passages, objections, replies, qualifications, examples, or counterevidence;
- concept substitution, terminology drift, equivocation, or collapsed distinctions;
- overstated scope, modality, or philosophical force, including source-reported novelty or consensus presented as independently established;
- mistaken attribution or dialectical role;
- reconstruction or charitable repair presented as textual fact;
- quotation, pagination, locator, symbol, translation, and edition accuracy;
- whether the report's evaluation remains distinct from what the source says.

Revise the analytical draft in response to the source and record unresolved problems. A Review pass that only rereads the draft is incomplete. This pass is internal verification within Source Analysis; it is not the separate Review workflow and does not satisfy a required exact-version Content Audit.

For partial or unreliable access, perform all three passes over all available material and keep the result provisional. If any required pass cannot be completed, state which pass failed and do not claim a completed full-source analysis.

## 3. Source project and genre

Identify, with evidence:

- the question, pressure, or purpose;
- thesis, governing interpretation, or central contribution;
- dialectical target;
- structure and turning points;
- method and source function;
- intended scope, modality, and qualifications;
- the debate as the author frames it.

Route by philosophical function rather than publication container. An authored handbook chapter may be an original argument; a journal article may be mainly historical or diagnostic.

## 4. Concepts and distinctions

For each load-bearing concept:

- preserve the source's term and relevant locator;
- identify whether it is defined, stipulated, inherited, operationalized, exemplified, or left implicit;
- distinguish definitions from slogans, examples, criteria, consequences, and nearby theses;
- record scope, contrast class, inferential role, and relation to neighboring concepts;
- track changes, ambiguity, equivocation, or unresolved variation;
- use a terminology bridge before comparing it with local vocabulary.

Do not assume two concepts are equivalent because translations or surface wording resemble one another.

## 5. Arguments and interpretive moves

For every central unit, record only the fields appropriate to its function:

```text
Unit type and provenance:
Claim, conclusion, interpretation, distinction, description, or result:
Grounds: premises, passages, cases, descriptions, derivation, or evidence:
Inferential, interpretive, conceptual, explanatory, formal, or normative link:
Scope, modality, and claimed force:
Hidden assumptions and burden:
Support type and exact support:
Objection or alternative and its provenance:
Author's reply, concession, and residual pressure:
Analyst reconstruction, repair, objection, or evaluation:
Locator:
```

Assess separately the strength of the link, the support for premises or interpretation, and any external criticism. A valid inference does not establish its premises; a plausible premise does not repair an invalid bridge.

For interpretive claims, distinguish textual evidence, contextual assumptions, interpretive principle, rival reading, edition or translation issue, and present philosophical evaluation.

## 6. Genre-sensitive checks

### Argument-driven work

Reconstruct claims, grounds, inference, objections, replies, burden, and scope. Do not force every support relation into deductive form.

### Historical or exegetical work

Separate primary-text claims, passages, historical context, conceptual change, reception or transmission claims, rival readings, interpretive method, and present assessment. Guard against anachronism.

### Phenomenological or descriptive work

Identify the phenomenon, standpoint, descriptive procedure, experiential structure, and claimed generality. Separate description from introspection, case narrative, causal explanation, metaphysics, and normative inference.

### Genealogical, critical, or diagnostic work

Identify the target practice or concept, explanatory genealogy, critical standard, debunking or vindicatory force, and the bridge from diagnosis to conclusion.

### Formal work

State syntax, semantics, definitions, axioms or assumptions, derivation, model or countermodel, and informal target. Check validity, consistency, formalization adequacy, and whether the philosophical interpretation exceeds the formal result.

### Normative work

Identify the normative target, claim type, bearer, scope, strength, reasons or values, bridge principles, conflicts, priority, feasibility, defeat, and residual demands. Distinguish grounding, justification, weight, enablement, and defeat.

### Cases and thought experiments

Record stipulations, imported assumptions, target concept or principle, intended verdict, modal status, variants, possible confounds, and inferential role. Test whether the case illustrates, supports, diagnoses, pressures, or refutes.

### Empirically informed philosophy

Identify the empirical claim, design, result, and warranted scope only to the needed depth. Then state the philosophical premise it bears on, the bridge, and the conclusion. Mark technical validity for specialist checking when load-bearing.

### Surveys and overviews

Map topic architecture, distinctions, positions, omissions, and organizing narrative. Do not present the source's taxonomy as settled field history.

## 7. Objections and evaluation

Label each objection as author-raised, source-reported, analyst-generated, or researcher-generated. State its exact target and whether it is internal or external. Give the strongest plausible version, the reply if any, its cost, and residual pressure.

Do not invent an objection merely to make the analysis appear comprehensive. Do not silently repair a contradiction or attribute the repair to the author.

## 8. Debate framing and research role

Reconstruct how the author presents rivals, allies, foils, precursors, and sources of machinery. Separate this self-positioning from independently checked debate history.

Assign a possible research role only when supported: primary evidence, interpretation, target, rival, partial ally, conceptual resource, methodological model, case source, objection source, background, or lead. Do not infer support, criticism, influence, or debate participation from citation, keyword overlap, chronology, graph proximity, or similar wording alone.

When project context exists, an optional Project Relevance rating uses a 0–10 scale with 5 as the passing threshold. A passing score requires at least one concrete, warranted use for the stated project. The score measures project relevance only; it is not a judgment of truth, philosophical quality, source reliability, prestige, review status, or evidential authority. Give a short rationale and omit the rating when project context is absent or too indeterminate.

Separately, an optional **Debate Importance** rating may assess the source's importance within one explicitly named debate, domain, tradition, period, or reception context. Include it only when the researcher requests prioritization or the active Analysis workflow explicitly calls for this property; ordinary Source Analysis need not produce another rating. Use a whole-number 0–10 scale:

- `0` — no identifiable role in the assessed debate;
- `1–2` — peripheral or mainly illustrative;
- `3–4` — relevant but limited intervention or background;
- `5` — materially important to a competent understanding of the named debate;
- `6–7` — substantial intervention, reference point, or durable source of pressure;
- `8–9` — major, agenda-setting, canonical, or structurally pivotal contribution;
- `10` — constitutive landmark for the assessed debate; use rarely and only with strong contextual evidence.

Debate Importance has no pass grade and is not universal importance. It is distinct from project relevance, philosophical quality, truth, current popularity, citation count, prestige, and the author's own importance claim. Assign it only when checked contextual evidence is sufficient to compare the source's role within the named scope. Record the scope and a short evidence-based rationale. If the rating was requested but the evidence is insufficient, omit both properties and state `not assessed`; if it was not requested, omit the section without comment.

Treat a rating made during one Source Analysis as a context-bound assessment, not a permanent field verdict. Compare or sort ratings only within the same explicit Debate Scope. When a large Analyses corpus needs consistent prioritization, use one bounded Research Synthesis to recalibrate the included sources against a common debate map and common anchors. The optional `research-explorer` Practice may strengthen the contextual judgment, but no additional Assessor Skill is required. Reviewer evaluates philosophical work; it does not independently determine a source's historical or structural importance in a debate.

Unread bibliography items remain leads. Record why a lead may matter and what must be verified.

## 9. Output forms

For complete access, use a thorough or concise report proportionate to the request and interpretive risk. For partial access, use a provisional report that states both what can and cannot responsibly be claimed.

A durable report should normally include:

```text
Metadata and access:
Session analysis unit and pass completion:
Durable Research Unit after this analysis:
Scope, depth, and source function:
Question, thesis, method, and structure:
Debate-framing profile:
Concepts and distinctions:
Central analytical units with layer labels and locators:
Objections, replies, concessions, and residual pressure:
Evaluation and unresolved alternatives:
Verified research roles or candidate uses:
Debate Importance, assessed scope, and rationale, only when requested; otherwise a not-assessed reason only if requested:
Bibliographic leads requiring verification:
Open questions and next checks:
```

Never claim full-source analysis, direct quotation, precise page support, novelty, field consensus, or project relevance beyond the evidence inspected.
