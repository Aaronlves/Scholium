---
name: scholium-analyze
description: Analyze or reanalyze one paper into its current Analysis note, reconstructing before critical pressure and preserving exact evidential limits. Use for the Analyze Action on an Analysis Target with Scholium source access or an external Zotero/MCP paper-data route.
---

# Analyze

Apply `scholium-core-protocol`. If no authenticated Run exists, enter through
its project-discovery route before applying this Skill.

Analyze one explicit source and update only the current Analysis Target. Decide from the existing Analysis and source whether this is an initial analysis or a reanalysis; do not ask the researcher to choose a mode.

## Nonnegotiable boundary

- Inspect the exact paper data available through the selected route. Scholium
  may supply a path-free source reference and source-range pages, or the Agent
  may retrieve the bound paper through its independent Zotero/MCP capability.
  Metadata, an abstract, a citation, or the existing Analysis alone cannot
  substitute for inaccessible paper text.
- If the required paper unit cannot be accessed, report the precise limitation
  and narrow the claim to the accessible unit; do not claim that the paper was
  fully analyzed.
- Keep the source author's claims, cited positions, the researcher's existing notes, and your reconstruction or evaluation visibly distinct.
- Modify only the current Analysis. Materials and source files remain read-only.

## Method

Read `references/method.md` and perform its three passes. Read
`references/method-fit.md` when the source's philosophical method,
cross-disciplinary inference, or methodological adequacy materially affects
the reconstruction or evaluation. Read
`references/literature-recommendations.md` before deciding whether the source
grounds any `literatureRecommendations` items. Reconstruct concepts and
arguments before applying critical pressure. Critical testing is part of
Analyze, not a separate interface mode, but it must never be presented as the
source author's own position.

## Philosophical lenses

Philosophical lenses are methodologically substantive references within this
Skill, not separate authority objects. Select the smallest lens set that fits
the source and question, then read the corresponding reference before doing
the affected work:

- `references/Argument-Reconstructionist.md` for premise, inference, bridge,
  objection, and argument-strength reconstruction;
- `references/Conceptual-Analyst.md` for concepts, distinctions, definitions,
  uses, and conceptual dependencies;
- `references/Historical-Interpreter.md` for historically situated or
  textually disputed interpretation;
- `references/Research-Explorer.md` for bounded question, gap, method-fit, or
  research-direction exploration.

Use no lens by default merely to make the report look comprehensive. Once a
lens is selected, its evidential distinctions and safeguards are part of this
Skill's method.

Before submitting, perform one bounded fidelity self-check against the exact
saved Analysis revision and the source data actually inspected. Check source
attribution, conceptual and argumentative reconstruction, evidential roles,
and citations when source evidence permits. Record any unresolved issue or
unavailable check in the Analyze result and limitations. This is part of the
Analyze method: it does not create, attach, or require a separate Check
Fidelity Action or child Run. Keep `fidelity_outcomes` empty when submitting
the Analyze Result; that field is reserved for a researcher-initiated Check
Fidelity Run. Put the self-check's relevant limits in the frozen Analyze
academic Result fields, especially Reliability, or in an applicable limitation.

Revise the existing Analysis in place when warranted. Preserve useful uncertainty, competing interpretations, exact locators, and unrelated researcher-authored material. Do not create a new source-centered note when the current Analysis is the designated home.

## Feedback

Report in first person:

- the exact paper or source unit, retrieval route, and Materials actually inspected;
- whether the run was initial analysis or reanalysis;
- what changed and what was deliberately left unchanged;
- access limits, uncertain reconstructions, and unresolved objections;
- the source's operative method and success conditions when method fit was
  material, including implications or connections established by the source;
- any source-grounded literature recommendations; omit the optional field when
  there are none;
- any Topic contribution worth considering in a separately authorized Synthesize run.
