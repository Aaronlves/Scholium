# Research-Synthesis Method

## 1. Fix the synthesis object

State the question, source and note boundary, intended use, relevant time or tradition boundary, and relation types that matter. Identify whether the output is exploratory, comparative, planning-oriented, or a basis for a later authorized update.

Synthesis is not a pile of summaries and not a shortcut to a thesis. It makes relations explicit across already inspected material.

## 2. Preserve evidential layers

Classify each item as appropriate:

- primary source text or verified source claim;
- source's report of another view;
- source-analysis report;
- source-supported interpretation;
- reconstruction or charitable repair;
- researcher-authored note or commitment;
- criticism or evaluation;
- synthetic relation;
- agent proposal.

Do not cite an analysis report, note, or prior Dialogue as though it were the primary source. Do not let fluent synthesis erase the difference between what sources say and what the researcher proposes.

## 3. Build the map

Map only what the bounded materials support:

- motivating problem and stakes;
- positions, versions, and commitments;
- concepts, definitions, distinctions, and contrast classes;
- arguments, premises, conclusions, bridges, and dependencies;
- objections, replies, concessions, burdens, and residual costs;
- cases, examples, descriptions, formal results, and empirical premises;
- source roles, interpretive alternatives, and unresolved gaps.

Organize literature by philosophical question and dialectical role when possible. Use chronology only when it explains conceptual or debate development.

## 4. Type and test relations

Use the narrowest supported relation, such as:

- supports;
- undercuts;
- rebuts;
- objects to;
- replies to;
- depends on;
- contrasts with;
- qualifies;
- develops;
- interprets;
- compares with;
- historically influences;
- supplies a concept, case, method, or terminology;
- possible use;
- unresolved relation.

For every important relation, state its basis and status:

- established by checked evidence;
- source-supported;
- reconstructed;
- plausible;
- provisional;
- unknown.

Do not infer support from co-occurrence, influence from chronology alone, agreement from similar wording, criticism from opposed vocabulary, equivalence from translation, or debate participation from a citation.

## 5. Diagnose structure and pressure

Identify:

- central dependencies and bottlenecks;
- inconsistent uses of concepts;
- comparisons operating at different levels;
- tensions requiring resolution or qualification;
- missing premises, sources, or rival positions;
- source roles that exceed their evidence;
- possible contribution sites;
- places where compression would produce false unity.

Preserve incompatible but defensible reconstructions. Do not decide the researcher's position merely to make the map neat.

## 6. Calibrate Debate Importance when requested

For a large Analyses corpus, one bounded synthesis may compare or recalibrate Debate Importance without creating a separate Assessor workflow.

1. Fix one explicit Debate Scope shared by every compared rating.
2. Include only Analyses whose source roles and contextual evidence are adequate for comparison; leave the rest `not assessed`.
3. Apply the Source Analysis 0–10 anchors consistently across the bounded corpus.
4. Explain each rating through the source's structural role in the debate, not citation count, prestige, familiarity, usefulness to the current project, or philosophical agreement.
5. Preserve a prior rating when no better comparative basis exists. If a changed map warrants recalibration, state why the old and new judgments differ.
6. Write `debate_importance` and `debate_importance_scope` only when the exact Analysis files and both properties are in the authorized write set. Otherwise return a candidate calibration table.

Ratings from different scopes are incommensurable. Do not produce a global ranking across debates merely because the properties share one numeric scale.

## 7. Return decisions

End with the smallest useful next decisions: verify one relation, inspect a source, clarify a concept, reconstruct an argument, test an objection, or choose among explicitly compared directions.

Stop a relation at `unknown` when evidence is insufficient. Move to source analysis when a text requires close interpretation; move to development when the researcher wants to construct a position; move to writing only after the map's load-bearing relations are stable enough for prose.
