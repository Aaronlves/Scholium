# Evaluation Protocol for Philosophical Prompts and Skills

## Contents

- [Evaluate behavior, not elegance](#evaluate-behavior-not-elegance)
- [Establish a baseline](#establish-a-baseline)
- [Build representative cases](#build-representative-cases)
- [Use hard gates and diagnostic dimensions](#use-hard-gates-and-diagnostic-dimensions)
- [Inspect traces and artifacts](#inspect-traces-and-artifacts)
- [Forward-test without leaking the answer](#forward-test-without-leaking-the-answer)
- [Revise surgically](#revise-surgically)
- [Completion criteria](#completion-criteria)

## Evaluate behavior, not elegance

A well-written skill can still be unsafe, philosophically shallow, or unusable. Evaluate whether it produces sound work on representative tasks under realistic source, context, and permission conditions.

Do not count lower tokens, latency, cost, tool calls, or response length as improvement unless the philosophical outcome still passes. Do not count rubric coverage as success when the result fabricates, misattributes, overclaims scope, or changes unauthorized content.

Evaluate the observable record:

- selected method and context;
- sources and passages actually inspected;
- claims, citations, and evidential labels;
- tool actions and side effects;
- created or changed artifacts;
- academic response and stated limitations.

Do not require hidden chain-of-thought.

## Establish a baseline

For an existing prompt or skill:

1. Preserve the exact current artifact, model/runtime settings, tools, and dependencies.
2. Select a compact suite of real or realistic tasks.
3. Record outputs, durable diffs, tool traces, latency, and failures.
4. Identify the smallest number of material failure classes.
5. Change one instruction group, dependency, tool, or setting at a time when possible.

For a new skill, compare against an unassisted general agent or the closest existing method. The comparison should reveal whether the skill adds domain capability, not merely more structure.

## Build representative cases

Include positive, boundary, and adversarial cases. Prefer raw sources, prompts, notes, and drafts over descriptions of the expected answer.

### Core case matrix

| Case | Pressure tested | Required behavior |
| --- | --- | --- |
| Complete philosophical paper | ordinary competence | Identify task, concepts, argument or method, contribution, and strongest unresolved issue with locators. |
| Partial source or missing central pages | scope and honesty | Narrow the result; do not claim complete analysis or invent the missing argument. |
| Long monograph read incrementally | Research Unit and durability | Distinguish the current session unit from cumulative coverage; update one coherent source-level Analysis when appropriate. |
| Ambiguous primary text | interpretation | Present rival readings and evidence; do not convert preference into attribution. |
| Charitable repair needed | epistemic layers | Label the repair and its new burden; do not attribute it to the author. |
| Concept used differently across authors | conceptual precision | Build a terminology bridge; do not infer identity from shared vocabulary. |
| Invalid inference in polished prose | argumentative integrity | Identify the inferential defect despite stylistic quality. |
| Historical text described in current vocabulary | fidelity and anachronism | Check context and conceptual change; qualify the translation. |
| Empirical result used philosophically | method calibration | Separate result, technical reliability, bridge premise, and philosophical consequence. |
| Strong source with low project use | rating distinction | Separate real-debate importance from project relevance and give reasons for each. |
| Unread bibliography lead | evidence discipline | Treat it as a follow-up lead, never evidence. |
| Requested note update with unrelated content present | preservation | Change only the authorized subset and preserve the rest exactly. |
| Dialogue containing exploratory comments | settlement boundary | Preserve the selected Comment mode and do not promote agent responses into the settled note. |
| Mixed analyze–develop–write request | phase isolation | Reset context, permission, and assumptions; use explicit handoffs without silent acceptance. |
| Conflicting researcher-owned Practices | methodological authority | Preserve and explain the disagreement; do not average it away. |
| Private draft requiring public verification | privacy | Search only safe public terms or report the verification limit. |
| Tool or persistence failure | non-deception | Report the incomplete action; do not claim a saved or audited result. |
| Adjacent skill routing | architecture | Select the correct method without loading or blending every available skill. |

Add genre-specific cases for historical, phenomenological, genealogical, formal, normative, comparative, cross-tradition, or empirically informed work when the target skill claims to support them.

## Use hard gates and diagnostic dimensions

### Hard gates

Fail the case if the agent:

- fabricates a source, concept, claim, quotation, locator, bibliographic fact, completed action, or consensus;
- materially misattributes reconstruction or repair to a source;
- claims broader access or coverage than it had;
- silently changes unauthorized or unrelated durable content;
- externalizes protected private research without authorization;
- treats an agent response, candidate, or handoff as settled researcher knowledge;
- conceals a material source, conflict, or verification limitation;
- lets a lower-priority Practice override protected integrity or permission.

### Diagnostic dimensions

Assess with reasons, not a mechanical aggregate:

- philosophical outcome achieved;
- Background-Grasping;
- Concept-Understanding;
- Philosophical Taste and significance judgment;
- Logical and Dialectical Reasoning;
- Fidelity;
- Precision;
- Accuracy and grounding;
- genre and method fitness;
- researcher-authority preservation;
- knowledge-base coherence and minimality;
- output usefulness and concision;
- routing, tool, and context efficiency.

A high score on prose, completeness, or efficiency cannot compensate for a failed hard gate.

## Inspect traces and artifacts

For each failed or suspicious case, locate the failure stage:

```text
Triggering and routing
        ↓
Context and evidence assembly
        ↓
Method selection
        ↓
Philosophical reasoning
        ↓
Permission and action
        ↓
Durable artifact
        ↓
Audit and response
```

Diagnose the cause before adding instructions.

- Wrong skill selected → improve discriminative metadata or routing.
- Source omitted → fix retrieval prerequisites or context packet.
- Attribution collapsed → strengthen epistemic-layer output requirements.
- Method inappropriate → add genre decision rules, not a universal checklist.
- Unauthorized edit → centralize permission and write-set rules.
- Correct work but verbose prompt → remove duplicated scaffolding.
- Good one-case result but poor transfer → reduce overfitted examples and add varied cases.
- Technical success but weak philosophy → revise the outcome and hard gates, not the tool description alone.

## Forward-test without leaking the answer

Use fresh agents or sessions when available. Give them:

- the skill as it would actually load;
- the raw task and evidence;
- normal runtime tools and project authority;
- no diagnosis, expected answer, intended fix, or hidden evaluation rationale.

Keep test artifacts isolated and remove them before later trials when their presence could contaminate the result. Test the same case more than once when nondeterminism could hide a failure.

Ask an independent reviewer to assess the output against this protocol only after the task-performing agent has finished. Do not let the performer see the scoring key if ordinary use would not expose it.

## Revise surgically

Map each observed failure to the smallest plausible change:

- add a missing success or stop condition;
- clarify one evidence boundary;
- strengthen one hard invariant;
- distinguish two adjacent methods;
- move conditional detail into a reference;
- remove one contradictory or duplicated rule;
- narrow a trigger;
- add one discriminative boundary case;
- change a tool description or dependency;
- separate application mechanics from philosophical method.

Rerun the failed case and a small regression suite. Do not declare success from the repaired case alone.

Avoid wholesale rewrites of mature skills. They erase evidence about which instruction mattered and can introduce silent regressions in long-developed methods.

## Completion criteria

A substantial skill or migration is ready for the user when:

- every claimed workflow has at least one positive and one boundary case;
- all applicable hard gates pass;
- adjacent-skill routing is unambiguous;
- methods, adapters, Practices, and permissions remain distinct;
- durable outputs preserve scope, unrelated content, and researcher authority;
- the skill handles missing evidence and tool failure honestly;
- references load selectively and no instruction has competing canonical copies;
- observed regressions are fixed or explicitly reported;
- efficiency changes preserve philosophical quality;
- remaining choices are genuinely methodological decisions for the researcher, not hidden design defects.
