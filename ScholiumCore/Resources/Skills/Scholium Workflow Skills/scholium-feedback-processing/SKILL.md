---
name: scholium-feedback-processing
description: Process received philosophical feedback in Scholium from supervisors, advisors, committee members, editors, referees, examiners, peers, or other readers. Preserve each comment, identify its concern and affected material, recommend an explicit disposition, and produce bounded revision tasks and response language. Use only for actual received feedback; do not use for independent peer review or self-generated criticism.
---

# Scholium Feedback Processing

Apply `scholium-core-protocol`. Treat feedback as evidence about a reader's response, not as automatic philosophical authority.

## Establish the feedback packet

```text
Mode: feedback
Feedback source and context:
Target work and exact version:
Feedback items:
Read set:
Write set:
Permission:
Output:
Stop condition:
Durability:
```

Process in chat or candidate form by default. Do not revise the target while determining dispositions unless the task separately authorizes that revision phase.

## Load the method

Read [references/method.md](references/method.md) completely.

## Apply selected Philosophical Practices

If an explicit Practice is selected, load only that researcher-owned reference plus `COMPOSITION-RULES.md`, and record its stable ID and package revision; otherwise load no Practice. Compatible Practices are `reviewer`, `dialectical-partner`, and `systematizer`. A Practice may refine analysis of a concern but cannot decide the researcher's disposition.

## Execute

1. Preserve the comment verbatim or as a clearly labeled faithful paraphrase.
2. Separate explicit request, stated reason, underlying concern, and implied demand.
3. Locate the affected passage, concept, argument, source use, structure, or project decision.
4. Classify the issue without exaggerating it.
5. Test the feedback against the work and available evidence.
6. Recommend one canonical disposition and explain why.
7. Record the researcher's disposition when supplied.
8. For accepted or partly accepted items, create the smallest defensible revision task and checks to rerun.

## Return

For each item:

```text
Feedback item:
Faithful request or concern:
Issue type:
Affected material:
Evidence and project fit:
Recommended disposition:
Researcher disposition:
Reason:
Bounded revision task:
Checks to rerun:
Possible response to the reader:
Researcher decision needed:
```

End with a disposition summary, unresolved conflicts, and the next authorized workflow. A recommended disposition is not the researcher's decision.
