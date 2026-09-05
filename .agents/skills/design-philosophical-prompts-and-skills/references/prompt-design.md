# Philosophy-Facing Prompt Design

## Contents

- [Translate general prompting into philosophical work](#translate-general-prompting-into-philosophical-work)
- [Use an outcome-first contract](#use-an-outcome-first-contract)
- [Engineer the context stack](#engineer-the-context-stack)
- [Set degrees of freedom](#set-degrees-of-freedom)
- [Define intellectual collaboration](#define-intellectual-collaboration)
- [Define evidence and retrieval](#define-evidence-and-retrieval)
- [Define autonomy and permission](#define-autonomy-and-permission)
- [Route tools and context](#route-tools-and-context)
- [Control response and Dialogue semantics](#control-response-and-dialogue-semantics)
- [Handle long and mixed workflows](#handle-long-and-mixed-workflows)
- [Migrate between models](#migrate-between-models)
- [Simplify safely](#simplify-safely)

## Translate general prompting into philosophical work

Use general model guidance only after translating it into the domain's real success conditions.

| General principle | Philosophical translation |
| --- | --- |
| Define the outcome | Name the interpretation, reconstruction, critique, revision, synthesis, or durable knowledge capability the researcher needs. |
| State success criteria | Require warrant, scope, source fidelity, conceptual precision, argumentative adequacy, and an appropriate output. |
| Bound evidence | State what texts, passages, notes, Dialogue, project context, and external scholarship may support the result. |
| Bound autonomy | Separate reading, analysis, proposals, direct edits, external disclosure, and settled knowledge. |
| Expose relevant tools only | Provide only the source, retrieval, writing, verification, and persistence mechanisms needed for this task. |
| Add stop rules | Stop or narrow when access, source support, permission, or a material researcher decision is missing. |
| Validate | Test on real philosophical sources, arguments, drafts, and knowledge-base changes. |

Do not inherit coding-agent defaults such as treating tests passing, files changing, or commands succeeding as the primary result. In an application adapter, those facts matter only because they protect or deliver a scholarly outcome.

## Use an outcome-first contract

Prefer a compact contract that states the destination and the hard boundaries:

```text
Function: Reconstruct and assess the source's central argument.

Outcome: A source-faithful argument map that distinguishes attribution,
reconstruction, and evaluation and identifies the strongest unresolved pressure.

Evidence: The declared source unit, verified locators, and explicitly supplied
project context. Unread sources may be follow-up leads but not evidence.

Success: The map covers the load-bearing claims, grounds, inferential links,
scope, objections, replies, and limitations without overclaiming access.

Boundary: Do not update project notes. Do not invent missing premises as the
author's. Stop or mark the result provisional if the central pages are missing.

Output: Concise analytical report plus clearly labeled handoff candidates.
```

Prescribe every step only when the order has epistemic value. A three-pass source method, for example, may be justified because orientation, reconstruction, and source-grounded review perform different checks. Routine browsing or file operations normally do not need narrative micromanagement.

## Engineer the context stack

Treat the task prompt, always-on instructions, skills, tools, memory, references, and current research artifacts as one assembled context. Before adding guidance, map which layer already owns it and inspect the assembled stack for contradictions. Resolve a conflict at its canonical owner; do not add a louder duplicate elsewhere.

Prefer this distribution:

- **thin task prompt** — current purpose, scope, researcher choice, and requested result;
- **thin always-on layer** — product identity, stable high-risk invariants, and non-obvious environmental constraints;
- **thin skill entry point** — discriminative routing, intellectual function, decision boundaries, and a map to conditional methods;
- **expressive interfaces** — tool parameters, return schemas, permissions, and failure states that make the available action space legible without walkthroughs;
- **rich bounded artifacts** — primary texts, active notes, drafts, Dialogue, analyses, rubrics, schemas, and verified task state carrying the detailed context for this task.

Do not turn an instruction file into a central repository for all possibly relevant practices or project facts. Select the smallest sufficient set of rich artifacts, preserve their evidential roles, and use progressive disclosure for conditional detail. A large context window does not justify loading unrelated sources or an entire skill library.

Prefer interfaces and decision rules over examples when the agent can infer a good route from the research object and available operations. Keep an example only when it discriminates a real boundary, such as source attribution versus charitable repair or advisory writing versus an authorized note edit. Treat examples as tests of a rule, not as the default exploration space.

Simplification must be risk-sensitive. Retain explicit low-freedom constraints for fabrication, source fidelity, attribution, privacy, permission, conflict handling, researcher authority, and preservation of durable work. Let judgment replace prescriptive scaffolding only where representative philosophical evaluation shows that the stronger instruction is unnecessary.

## Set degrees of freedom

Use **low freedom** for fragile invariants:

- no fabricated sources, concepts, quotations, locators, claims, or completed actions;
- exact permission, privacy, write-target, and conflict rules;
- source/analysis/researcher-commitment separation;
- preservation of researcher-authored content and current document revisions;
- required schemas whose invalidity would corrupt a durable artifact.

Use **medium freedom** for preferred scholarly procedures:

- argument reconstruction fields;
- source-analysis passes;
- review sequences;
- response modules;
- status transitions;
- handoff and audit contracts.

Use **high freedom** for substantive philosophical judgment:

- selecting the strongest objection;
- deciding which distinction is load-bearing;
- determining whether two interpretations remain live;
- choosing an expository route appropriate to the argument and audience.

Do not replace judgment with keyword routing, fixed counts, automatic scores, or rigid templates. Do not use `always`, `never`, `only`, or `must` for mere preferences.

## Define intellectual collaboration

Separate voice from collaboration behavior.

- **Voice** controls directness, warmth, formality, density, and polish.
- **Collaboration** controls when the agent challenges a claim, asks a question, makes an assumption, pursues a source check, proposes a revision, or leaves a decision to the researcher.

Keep both concise. Prefer an intellectually candid, charitable, precise, non-sycophantic collaborator. Do not ask the model to claim human credentials, personal scholarly experience, publication status, or authority it does not possess. A phrase such as “act as a philosopher with fifty years of experience” is weaker than explicit standards for interpretation, concepts, arguments, evidence, objections, and writing.

Require the agent to:

- state disagreement with reasons rather than mirror the researcher;
- interpret charitably without shielding a view from serious criticism;
- ask only for information that materially changes the result;
- make bounded assumptions visible and revise them when evidence changes;
- preserve the researcher's voice without flattering, imitating, or overwriting it;
- omit generic praise, reassurance, and ceremonial sign-offs.

For length control, name what must survive compression: the conclusion, grounds, evidence, material qualification, strongest objection, uncertainty, and next decision. Remove repetition, generic background, and technical narration first.

## Define evidence and retrieval

State:

- what counts as the research object;
- the exact coverage or Research Unit when relevant;
- which sources are authoritative for attribution, interpretation, debate history, bibliography, or empirical claims;
- whether project notes are evidence, context, or records of researcher commitments;
- when external research is required;
- what to do with partial, OCR-corrupted, inaccessible, conflicting, or suspiciously narrow material.

Require one or two meaningful retrieval fallbacks when a required source lookup is empty or incomplete. Do not retrieve repeatedly only to improve phrasing or add decorative background.

For grounded work:

- cite only inspected or retrieved sources;
- attach locators or citations to the claims they support;
- distinguish direct support from inference;
- report conflicts and unresolved checks;
- treat absence of retrieved evidence as “not established,” not automatically false;
- protect unpublished research when forming external queries.

## Define autonomy and permission

Keep the action policy compact and centralized.

- **Answer, explain, analyze, review, or diagnose** — inspect relevant material and return the intellectual result; do not edit durable artifacts unless requested or the active workflow explicitly includes authorized updates.
- **Create, revise, integrate, or update** — make only the named in-scope durable changes and perform relevant non-destructive validation.
- **Propose** — return candidates or patches without silently applying them.
- **Externalize** — require an explicit safe-to-disclose boundary for private research content.
- **Expand scope** — stop or report the additional target when it lies outside the original task.

Permission does not flow from intellectual mode. Analysis can be read-only; writing can be advisory; Dialogue can produce an agent response without changing a note. In a multi-phase workflow, recompute permission and the write set for every phase.

## Route tools and context

Expose only task-relevant tools. Describe each tool by:

- scholarly purpose;
- when it is required;
- inputs and important return fields;
- trust or access boundary;
- error and fallback behavior;
- whether it reads, writes, externalizes, or merely derives.

Require prerequisite retrieval before claims or actions that depend on it. Parallelize independent reads, then synthesize; keep dependent philosophical judgment sequential.

Do not ask an agent to scan arbitrary global skill directories, unrelated vaults, another agent's configuration, or private files merely because they are technically reachable. Use a bounded catalog or explicit source list.

Use deterministic scripts or structured processing for mechanical work such as schema validation, deduplication, sorting, or locator checks. Keep interpretation, source-role judgment, conceptual comparison, and final evaluation in explicit model judgment.

Use programmatic or batched tool orchestration only for a bounded mechanical stage, such as filtering a large catalog, joining bibliographic records, deduplicating notes, or validating repeated schemas. Declare the eligible tools, compact output schema, retry limit, and handoff back to semantic judgment. Do not let a reduction stage discard citations, evidential status, minority interpretations, or qualifications needed for the philosophical result.

## Control response and Dialogue semantics

Define what the researcher needs to know, not what the runtime happened to do.

Prefer:

```text
Academic result or change:
Evidence or material checked:
Strongest unresolved issue:
Researcher decision needed:
Durability or integration status:
```

Omit routine file counts, token use, model details, and operation logs unless they reveal an integrity failure, conflict, or incomplete action.

For Dialogue, preserve scholarly interaction:

- researcher Comment;
- attributed agent Response;
- follow-up Comment and Response;
- material objections, qualifications, and changes of mind.

Do not require hidden prompts, system messages, temperature, token counts, or sentence-level generation lineage to become the scholarly record. Do not misrepresent a condensed Comment as verbatim. Do not treat a Response as the researcher's eventual decision.

Control length by specifying what must remain and what may be omitted. For example:

> Preserve the interpretation, reasons, qualification, unresolved objection, and next decision. Remove repetition, generic praise, implementation detail, and non-material conversational noise first.

## Handle long and mixed workflows

For long-running work, require a short initial orientation and sparse outcome-based updates at major phase changes. Do not demand narration of routine tool calls.

Use a mixed workflow only when the request genuinely contains distinct intellectual operations. Represent it as an ordered sequence of ordinary modes, not unrestricted simultaneous activation.

For each phase define:

```text
Mode:
Purpose:
Required method:
Read set:
Write set:
Permission:
Output:
Stop condition:
Durability expectation:
Handoff:
```

Reset context, assumptions, method selection, write subset, and permission between phases. Treat the preceding result as a labeled handoff, not automatically accepted knowledge. Run an exact-version audit once after the final substantive change unless an earlier independent audit is methodologically necessary.

## Migrate between models

Do not rewrite a working philosophical prompt stack merely because a new model guide exists.

1. Preserve the current prompt, tool set, model settings, and representative task set as the baseline.
2. Change the model first when possible and rerun the same cases.
3. Identify observed failures or obsolete scaffolding.
4. Remove one redundant instruction group, example family, or irrelevant tool at a time.
5. Add the smallest targeted instruction that repairs a measured regression.
6. Compare philosophical correctness and integrity before tokens, latency, cost, or call count.

Treat a vendor's reported prompt reduction as evidence that older scaffolding may be obsolete, not as a deletion target or universal ratio. A shorter stack is an improvement only when the same representative philosophical cases still pass and the assembled instructions are less contradictory.

Preserve the current reasoning-effort setting as the first comparison baseline. Test a lower or higher setting only on the same representative cases, and retain the change only when the observable philosophical result justifies it. Before increasing reasoning effort, check whether the prompt lacks a success criterion, evidence boundary, dependency rule, or verification loop.

Keep version-specific controls—reasoning effort, API fields, tool formats, prompt-cache behavior, or product capabilities—outside the timeless philosophical method when possible. Verify them against current official documentation before use.

Do not ask for hidden reasoning traces. Evaluate the observable result, evidence use, tool actions, citations, durable artifacts, and reported limitations.

## Simplify safely

First inspect the instructions as the agent receives them, including the user request, always-on authority, selected skills, tool descriptions, memory, and references. Identify duplicated, incompatible, stale, or wrongly placed guidance before editing any one file. Prefer deleting or relocating the noncanonical copy to restating the rule.

Remove:

- repeated statements of the same rule;
- generic reminders that do not change behavior;
- examples that do not distinguish a boundary case;
- tools unrelated to the selected workflow;
- duplicated methodology across entry files and references;
- role labels that merely rename the same intellectual function;
- model-specific workarounds no longer supported by evidence.

Keep:

- the philosophical outcome;
- success and stopping conditions;
- epistemic and permission invariants;
- evidence and source-routing rules;
- required output and durability semantics;
- the smallest examples needed to prevent a real failure;
- validation instructions tied to representative philosophical work.

After simplification, check for contradictions. Conflicting prompt contracts are usually more damaging than a missing optional detail.
