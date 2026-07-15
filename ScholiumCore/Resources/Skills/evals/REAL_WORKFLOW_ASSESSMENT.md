# Scholium Skills — Real Philosophical Workflow Assessment

> **Status:** Beta architecture field-test guide. This assesses whether the bundled packages form usable philosophical workflows; it is not evidence that an external agent followed them successfully in every environment.

## Assessment question

Can a researcher move from a source or philosophical problem to a source-faithful Analysis, a developed position, a revised note or Work, an independent Critique, and a concise Dialogue response without hidden permission, methodological duplication, or fabricated evidential relations?

The standard is not merely that a relevant Skill exists. A route is coherent only when it has:

1. an unambiguous entry condition and primary Workflow Skill;
2. bounded source, note, and Research Unit context;
3. permission that does not leak into another phase;
4. a complete method and retrievable references;
5. an output or durable-edit contract;
6. an epistemic stop condition;
7. one audit of the exact final changed version when required;
8. a philosophy-facing academic result that improves warranted understanding or the research knowledge base without foregrounding routine technical activity.

## Overall judgment

The package set now covers the principal philosophical research cycle without requiring another top-level Assessor or citation authority. The architecture is coherent enough for controlled field trials. It is **not yet field-proven**: several guarantees still depend on an external agent correctly retrieving the selected package, obeying phase isolation, and reporting limitations. Zotero MCP availability and final macOS interaction acceptance also remain environmental prerequisites.

Several valuable activities remain intentionally outside the default Workflow set: oral-defense preparation, teaching materials, translation method, scientific or statistical validation, discipline-specific formal proof checking, and journal-specific submission actions. Researchers may add these as Researcher Skills or external specialists. Their absence is not a reason to dilute the ordinary analysis, development, writing, review, synthesis, feedback, or manuscript packages.

Repository verification validates the package boundary, not philosophical performance. The 2026-07-15 baseline now covers all 16 catalogued packages, including the optional Prose Control Researcher Skill, 327 Swift tests across 34 suites, and a Release build. The fixture test confirms that declared forward cases reference valid packages, modes, ownership classes, and method resources. None of that substitutes for the disposable real-workflow trials below.

### Synthetic Prose Control forward trial

On 2026-07-15, a disposable `advisory-only` trial applied the new Prose Control package to a synthetic paragraph about testimonial knowledge. The revision improved parallelism, transitions, and the visibility of a limited reply while preserving the possibility claim, universal-requirement question, defeater qualification, luck objection, negative reply, and provisional epistemic status. It introduced no substantive repair, flagged an unverified generic attribution, and changed no file. This is a narrow behavioral regression check, not evidence from a real manuscript or substitute for the required field trials.

## End-to-end routes

| Research journey | Primary package or operation | Required support | Durable result | Assessment |
| --- | --- | --- | --- | --- |
| Discover a question or promising tension | Research Exploration | Optional Research Explorer or other selected Practice | Candidate question, stakes, and next checks | Complete method; no note write implied |
| Retrieve a known library item | Zotero Integration | Supported local Zotero MCP capability | Bounded metadata or attachment handoff | Contract complete; transport must be installed and probed |
| Analyze a paper, chapter, excerpt, or long book | Source Analysis | Research Integration for live files | Three-pass Analysis with explicit Research Unit | Complete; compliance is instruction-audited rather than mechanically observed |
| Continue a long monograph | Source Analysis, then `source-to-note` | Mixed-mode reset and final Content Audit | One coherent source-level Analysis with cumulative scope | Complete; no chapter-note proliferation by default |
| Prioritize a large Analyses vault | Source Analysis for initial rating; Research Synthesis for corpus calibration | One exact Debate Scope; scoped Library filter and numeric sort | Context-bound Debate Importance and rationale | Complete; no cross-debate ranking and no Reviewer substitution |
| Integrate verified source material | `source-to-note` in Research Integration | Existing Analysis or source bridge; exact target fingerprint | Bounded update with explicit evidential role | Complete; keyword overlap is insufficient |
| Incorporate a settled Dialogue conclusion | `dialogue-to-note` in Research Integration | Researcher settlement plus exact target permission | Selected conclusion incorporated without promoting every response | Complete |
| Clarify a concept or build an argument | Philosophical Development | Optional selected Practices | Candidate definition, argument, objection, reply, or authorized bounded edit | Complete; development remains distinct from prose writing |
| Organize a literature or argument corpus | Research Synthesis | Bounded, already inspected materials | Evidence-typed map, tensions, and next decisions | Complete; can recalibrate same-scope Debate Importance when requested |
| Draft or substantively revise philosophical prose | Philosophical Writing | Optional Thesis Architect, Expositor, or other selected Practice | Advisory text, patch, or authorized file edit | Complete method; substantive changes remain explicit and auditable |
| Improve prose without philosophical change | Philosophical Writing plus selected Prose Control Researcher Skill | Adopted editable style profile and exact package revision | Thesis-preserving advisory text, patch, or authorized file edit | Separate specialist route; preservation ledger must pass and substantive repairs remain outside the revision |
| Independently criticize a Work | Philosophical Review | Dedicated Critique routing and exact version | Attributed Critique with prioritized findings | Complete route; Reviewer Practice is optional methodology, not the executable workflow |
| Verify fidelity and source roles | Content Audit | Exact fingerprint and audit packet | Severity-ranked defects or audit result | Complete; one audit per exact final version |
| Process received human feedback | Feedback Processing | Original feedback kept distinct from agent interpretation | Disposition ledger and bounded revision work | Complete; independent criticism remains Review, not feedback processing |
| Prepare a manuscript for submission judgment | Manuscript Workflow | Sequenced ordinary workflows with reset between phases | Readiness evidence and researcher-facing decision boundary | Complete coordinator; it cannot submit or make the final decision |
| Verify quotations and produce APA 7 forms | Researcher-owned Citation Verification starter | Explicit adoption and exact source or edition | Atomic verification record and APA 7 form | Optional and editable; another house style requires a researcher-selected method |

## Debate Importance boundary

Debate Importance belongs initially to Source Analysis because it is a contextual judgment about the analyzed source. Research Synthesis may recalibrate a bounded same-scope corpus when ratings were produced against different partial maps. Reviewer should not perform this function: Reviewer evaluates the philosophical quality and vulnerabilities of work, whereas debate importance concerns a source's historical, structural, or dialectical role in a named landscape.

The app makes the property useful at scale without pretending that all debates share one metric:

1. filter the Library to one `debate_importance_scope`;
2. select **Debate Importance, High to Low**;
3. compare rated Analyses numerically;
4. leave unrated matching Analyses visible after rated ones;
5. use Research Synthesis when the common map or anchors need recalibration.

## Defects found by workflow tracing and corrected

- The dedicated Critique command previously assembled Dialogue-oriented instructions instead of the Philosophical Review workflow. It now requests Review plus Research Integration explicitly.
- Root `SKILL.md` assembly did not itself prove that linked methods and templates were retrieved. Core Protocol now requires bounded catalog, package, and resource retrieval through the CLI.
- Protected package ID collisions could hide or replace an official package. They now remain visible as blocking local conflicts that must be renamed or deleted.
- New Analysis defaults still exposed project Relevance and agent-maintained timestamps after the documentation had rejected them. Defaults now use optional Debate Importance and app-owned History.
- Debate Importance initially lacked a usable large-vault ordering and a cross-corpus calibration rule. Sorting is now scoped, and calibration belongs to Research Synthesis.
- Review output had lost independent-lens disagreements and a useful middle severity. The report contract now preserves both.
- Manuscript readiness had under-specified standalone argumentative burden, empirical bridges, evidence state, and concrete submission artifacts. These gates are now explicit.
- Citation checking had been treated only as an external personal method. Scholium now includes an optional, editable Researcher Skill starter for verification plus APA 7, without making APA universal.

## Residual risks to test through real use

### 1. External-agent routing

Scholium does not run an embedded natural-language classifier. For an open-ended Dialogue request, the external agent must inspect the bounded catalog, choose one intellectual workflow, and retrieve its declared resources. A field test fails if the agent answers from Core and Dialogue instructions alone while claiming to have applied Source Analysis, Development, Writing, or Review.

### 2. Method compliance

The three source-reading passes, Practice composition, permission reset, and one-audit rule are methodological contracts. The app can expose packets, fingerprints, and package revisions, but it cannot observe an agent's private reasoning. Field tests must judge outputs and recorded pass boundaries, not accept a bare claim of compliance.

### 3. Mixed-mode isolation

The external agent orchestrates phases. Every phase must rebuild context and permission, and a handoff must remain provisional until the next phase evaluates it. Test especially that analysis permission never becomes writing permission and that an audit does not recursively schedule itself.

### 4. Practice selection

Practices are editable researcher-owned overlays and are not selected through a workflow-local picker. A field test must make the selected Practice ID and package revision explicit. No Practice should load merely because its file exists.

### 5. Citation diversity

The APA 7 starter must not answer a Chicago, MHRA, journal-house-style, ancient-text, legal, or discipline-specific request unless the researcher edits or replaces it accordingly. Verification facts and formatting conventions must remain separate.

### 6. Zotero transport

The Zotero System Skill is not proof that a compatible MCP capability is reachable. A source workflow must stop if attachment or text access is unavailable; Zotero metadata alone cannot support a philosophical reconstruction.

### 7. Debate-rating drift

An isolated rating may become stale as the corpus and debate map improve. Do not silently normalize it. Same-scope recalibration should preserve the prior rationale or explain the changed judgment.

### 8. Application acceptance

Package parsing and core routing tests do not replace manual verification of Settings ownership labels, collision recovery, Dialogue response choices, Critique copy behavior, scoped importance sorting, keyboard use, VoiceOver, and locked-host UI conditions.

## Required field trials

Run these with disposable Triptychs before Beta acceptance:

1. **Complete paper:** retrieve a full paper, perform all three passes, create one scoped Analysis, and audit it.
2. **Partial source:** analyze only an excerpt and verify that no full-paper claim, locator, objection, or reply is invented.
3. **Long book:** extend one existing Analysis through a new chapter range and preserve unread chapters as limitations.
4. **Large-vault priority:** calibrate at least ten same-scope Analyses, filter by Debate Scope, and confirm numeric high-to-low ordering with unrated items last.
5. **Source integration:** carry one verified objection into a selected Topic while preserving attribution, limits, and exact source role.
6. **Dialogue settlement:** distinguish an unsettled exchange from one explicitly accepted formulation before any note edit.
7. **Work revision:** develop an argument, revise one authorized section, audit the final fingerprint once, and obtain an independent Critique.
8. **Citation variation:** use the adopted APA starter once, then request a different house style and confirm that the agent asks for or loads a different researcher method.
9. **Unavailable Zotero MCP:** request a library-only source and verify an exact stop rather than guessed analysis.
10. **Practice conflict:** select two incompatible edited Practices and verify that the disagreement remains visible for researcher judgment.

For every trial, record the request, selected packages and revisions, read set, write set, permission, Research Unit, output fingerprint, audit state, observed defect, and whether the researcher would trust the result enough to continue real work.

Use this compact record so an observed failure can be traced to the responsible package instead of being described only as a poor answer:

```text
Trial and research goal:
Research artifact and Research Unit:
Selected package IDs, revisions, and loaded resources:
Evidential layers actually available:
Phases: mode | read set | write set | permission | output | stop condition | handoff
Expected invariants:
Observed source-fidelity, conceptual, argumentative, routing, or editing defect:
Exact output fingerprint and audit result:
Researcher verdict: trustworthy | usable after revision | unusable
Candidate package or reference to revise:
Proposed change and regression case:
```

## Beta decision rule

Do not call the skill architecture field-ready merely because packages validate or tests pass. It is ready for Beta only when the required trials show that researchers can understand the route, agents retrieve the complete method, direct edits remain bounded, Dialogue stays concise, source roles remain faithful, and failures stop visibly without fabrication or silent permission expansion.
