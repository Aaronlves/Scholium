# Templates for Philosophical Prompt and Skill Design

Use these as starting structures, not mandatory forms. Omit fields that do not change behavior. Never let a template replace philosophical judgment or source evidence.

## Contents

- [Compact task prompt](#compact-task-prompt)
- [Reusable prompt design brief](#reusable-prompt-design-brief)
- [Skill entry skeleton](#skill-entry-skeleton)
- [Method reference skeleton](#method-reference-skeleton)
- [Application workflow contract](#application-workflow-contract)
- [Knowledge-base mutation packet](#knowledge-base-mutation-packet)
- [Mixed-mode phase contract](#mixed-mode-phase-contract)
- [Evaluation fixture](#evaluation-fixture)
- [Design handoff](#design-handoff)

## Compact task prompt

```markdown
Function: [Intellectual function, without fictional credentials]

Outcome: [Researcher-visible philosophical result]

Research object and scope:
- Object:
- Exact unit or domain:
- Research question:

Evidence and context:
- Available material:
- Source authority and access limits:
- Project context and its evidential status:

Success criteria:
- [Philosophical content criterion]
- [Fidelity/precision/accuracy criterion]
- [Output or durability criterion]

Method:
- [Only the decision rules or sequence that changes behavior]

Boundaries:
- [Attribution and non-fabrication]
- [Privacy and external retrieval]
- [Permission and scope]

Output:
- [Shape, length, locators, uncertainty, next decision]

Stop conditions:
- [Missing evidence, conflict, permission, or material researcher choice]
```

## Reusable prompt design brief

```markdown
# Design Brief

## Research capability

The researcher should be able to:

## Triggering situations

-

## Exclusions and adjacent methods

-

## Philosophical standards

- Foundational capacities used:
- Fidelity requirements:
- Precision requirements:
- Accuracy and evidence requirements:

## Inputs and context

- Required:
- Optional:
- Forbidden or out of scope:

## Autonomy and permission

- Read:
- Retrieve or externalize:
- Propose:
- Write:

## Output and durability

- Ephemeral response:
- Durable artifact:
- Status or audit effect:

## Failure behavior

-

## Representative evaluation cases

- Positive:
- Boundary:
- Adversarial:
```

## Skill entry skeleton

````markdown
---
name: skill-id
description: "What the skill does, concrete triggers, research objects, and exclusions that distinguish adjacent skills."
---

# Human-readable Skill Name

[One concise statement of the philosophical capability and governing boundary.]

## Apply governing integrity

[Name the non-fabrication, fidelity, precision, accuracy, researcher-authority,
and privacy requirements that must remain close to the entry point.]

## Classify the task

[Select mode or submode from intellectual purpose, evidence, context, and
permission. Do not use permission as the mode classifier.]

## Establish the task packet

```text
Mode:
Research object:
Scope:
Question or desired change:
Evidence and access:
Read set:
Write set:
Permission:
Output:
Stop condition:
Durability:
```

## Load the method

- Read `references/method.md` completely.
- Read each conditional reference only under its declared condition.

## Execute

[Give the shortest complete procedure or decision rules.]

## Validate

[Name philosophical and artifact checks.]

## Return

[Lead with academic outcome, evidence, uncertainty, decision, and durability.]
````

Do not create every referenced file by default. Use only the package resources the actual method needs.

## Method reference skeleton

```markdown
# [Method Name]

## Purpose

## Core philosophical question

## Entry conditions

## Foundational capacities

- Background-Grasping:
- Concept-Understanding:
- Philosophical Taste:
- Logical and Dialectical Reasoning:

## Evidence and epistemic layers

## Attend to

## Procedure or decision rules

## Genre or tradition calibration

## Output contract

## Safeguards

## Failure and stop conditions

## Boundaries and adjacent methods
```

Use only the foundational capacities that materially apply. Fidelity, Precision, Accuracy, non-deception, and researcher authority remain universal even when not repeated as optional dimensions.

## Application workflow contract

```markdown
# [Workflow]

## Philosophical outcome

## Complete packaged method or stable dependency

## Bounded context assembly

- Research object:
- Selected source/note/text/Dialogue:
- Project context:
- Optional researcher-owned Practices:

## Mode and submode

## Read, write, and permission boundary

## Tool or application adapter

## Handoff and durability

## Academic response

## Failure, conflict, and privacy behavior
```

The adapter must not replace the philosophical method. The package must not depend on the designer's private global skill directory.

## Knowledge-base mutation packet

```text
Intellectual purpose:
Target object and exact path or ID:
Research Unit before:
Research Unit after:
Current revision or fingerprint:
Source and evidence packet:
Selected content or change boundary:
Write set:
Permission:
Properties allowed to change:
App-owned or derived properties to preserve:
Status transition and criteria:
Conflict behavior:
Validation:
Dialogue response or handoff:
```

## Mixed-mode phase contract

```text
Phase:
Mode:
Purpose:
Required method and selected Practices:
Read set:
Write set:
Permission:
Output:
Stop condition:
Durability expectation:
Handoff status:
Context reset before next phase:
```

The phase write set must remain a subset of the original authorized scope. A handoff is input to the next phase, not an accepted commitment.

## Evaluation fixture

```markdown
# Evaluation Case: [Name]

## Raw researcher request

## Available evidence and access limits

## Applicable authority and permission

## Normal tools and dependencies

## Required observable outcomes

-

## Hard-gate failures

-

## Diagnostic dimensions

-

## Artifacts to inspect

- Response:
- Citations or locators:
- Tool trace:
- Durable diff:
- Reported limitations:

## Regression relations

- Cases that must be rerun after a fix:
```

## Design handoff

```markdown
## Result

[Created, revised, audited, or proposed artifact.]

## Ownership and deployment

[Universal, bundled official, researcher-owned, or project-local.]

## Philosophical safeguards

[Truth, fidelity, precision, accuracy, evidence, authority, privacy.]

## Architecture

[Method, workflow, Practice, adapter, references, and dependencies.]

## Validation

[Checks and representative cases actually run.]

## Researcher decision remaining

[Only a material methodological or product choice; otherwise “None.”]
```
