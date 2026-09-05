# Architecture for Philosophical Skills

## Contents

- [Separate intellectual and operational layers](#separate-intellectual-and-operational-layers)
- [Classify reusable artifacts](#classify-reusable-artifacts)
- [Define ownership and update policy](#define-ownership-and-update-policy)
- [Design a complete package](#design-a-complete-package)
- [Use progressive disclosure](#use-progressive-disclosure)
- [Compose methods without duplication](#compose-methods-without-duplication)
- [Design triggering and routing](#design-triggering-and-routing)
- [Protect philosophical Practices](#protect-philosophical-practices)
- [Package application workflows responsibly](#package-application-workflows-responsibly)
- [Audit architectural quality](#audit-architectural-quality)

## Separate intellectual and operational layers

Use a layered architecture when several kinds of instruction interact:

```text
Platform safety and active authority
        ↓
Application or system protocol
        ↓
Philosophical workflow or specialist method
        ↓
Researcher-owned Practice or local convention
        ↓
Current task facts and researcher choices
        ↓
Sources, notes, Dialogue, and other evidence
```

The arrows show assembly and constraint, not ownership of truth. A protected system protocol may govern safe context retrieval or file mutation, but it does not become a philosophical authority. A researcher-owned Practice may change method, but it cannot weaken source fidelity or grant write permission.

Keep the current researcher instruction high in practical authority for purpose, scope, and desired result, subject to safety and protected integrity boundaries. Resolve a conflict explicitly rather than silently blending incompatible instructions.

## Classify reusable artifacts

### Methodological skill

Define how to perform a complete intellectual activity, such as source analysis, philosophical writing, or peer review. Include genre calibration, evidence standards, procedure, safeguards, and output.

### Workflow skill

Apply a complete method in a research sequence. Add context assembly, submode selection, read/write boundaries, handoffs, status, and durability. Do not replace the method with app commands.

### Specialist skill

Perform a narrow task that should remain separable, such as citation verification, content auditing, feedback processing, formal checking, or a tradition-specific interpretive method. Do not make it universal merely because it is useful.

### Philosophical Practice

Provide editable methodological attention, criteria, and procedures—such as Historical Interpreter, Conceptual Analyst, Argument Reconstructionist, Dialectical Partner, Systematizer, Thesis Architect, Philosophical Expositor, or Reviewer. A Practice describes intellectual activity; it is not automatically an executable workflow or ownership group.

### System or application adapter

Tell an agent how to discover bounded context, invoke tools, read schemas, mutate safely, persist Dialogue, or communicate with an external service. Its purpose is to serve philosophical work. Keep technical detail out of the user-facing academic result.

### Router or orchestrator

Select one relevant workflow or sequence several ordinary modes. Do not duplicate full methods. Mixed orchestration must isolate context, permission, and handoff state between phases.

### Template

Specify a stable output shape. A template does not choose a method, supply evidence, grant permission, or establish the truth of a populated field.

## Define ownership and update policy

For every package state:

- who authored the method;
- who may edit it;
- whether updates replace it, create a new version, or never touch it;
- whether researchers may duplicate or fork it;
- which copy is canonical for a past artifact;
- how a selected revision is identified when reproducibility matters.

Use these broad patterns:

- **universal/global skill** — discoverable across projects, project-neutral, updated by its owner;
- **bundled official skill** — release-pinned, protected in the application, complete without the designer's private files;
- **researcher-owned skill or Practice** — editable, locally authoritative for that researcher, never silently overwritten;
- **project-local adapter** — encodes one workspace's paths, vocabulary, schema, or coordination rules and should not leak into a universal method.

Do not let a local package shadow a protected ID silently. Use explicit IDs, origins, revisions, and collision rules.

## Design a complete package

Use a concise entry file and only necessary resources:

```text
<skill-id>/
├── SKILL.md
├── agents/
│   └── openai.yaml
└── references/
    ├── method.md
    ├── submodes.md       # only when genuinely distinct
    └── output-contract.md # only when durable shape matters
```

Add scripts only for repeated deterministic operations. Add assets only when they are copied or consumed in produced artifacts. Do not add a README, changelog, installation guide, or duplicated quick reference to a normal skill package unless the hosting system separately requires it.

The frontmatter description must say what the skill does and the concrete situations that should trigger it. Do not rely on a “When to use” section that is invisible until after triggering. Keep frontmatter free of project secrets, paths, or volatile model advice.

Write the body in imperative language for the agent that will use it. State the core workflow, decision boundaries, required references, and output. Avoid explaining the design history.

## Use progressive disclosure

Load instructions in three levels:

1. **routing metadata** — name and discriminative description;
2. **entry instructions** — the core method, selection logic, boundaries, and reference map;
3. **conditional resources** — detailed genre checks, templates, schemas, examples, and specialist protocols.

Keep references one level away from `SKILL.md` where possible. Name the condition for reading each reference. Do not require every reference for every task.

Put a rule in one canonical place:

- keep universal philosophical invariants near the governing entry point;
- keep complete intellectual methodology in the method skill or its method reference;
- keep app mechanics in an adapter;
- keep researcher choices in Practices or local skills;
- keep output fields in one template or schema;
- keep current task facts out of stable package text.

## Compose methods without duplication

Before adding a skill, ask whether the proposed function is:

- a new intellectual activity;
- a submode of an existing activity;
- a specialist check;
- a Practice overlay;
- an application adapter;
- merely another output format.

Merge artifacts that share the same trigger, method, evidence, permission, and output. Keep them separate when they have different epistemic purposes or authority boundaries.

Important distinctions include:

- source analysis vs source integration;
- argument development vs prose writing;
- independent peer review vs content/source audit;
- feedback processing vs independent criticism;
- citation verification vs overall source assessment;
- Historical Interpreter vs a complete source-analysis workflow;
- Systematizer vs a synthesis workflow;
- Dialectical Partner vs Reviewer;
- Thesis Architect vs Philosophical Expositor;
- Practice reference vs executable workflow;
- philosophical method vs application adapter.

When a workflow depends on a canonical method, either package that method as an explicit stable dependency or include a complete project-neutral implementation. Do not partially paraphrase a mature method in several packages and let them drift.

## Design triggering and routing

Make descriptions discriminative enough to select the right skill without loading all bodies.

Include:

- the intellectual operation;
- relevant research objects or genres;
- important exclusions that distinguish adjacent skills;
- whether it creates, reviews, integrates, or only advises;
- any essential application or tool context.

Avoid descriptions so broad that every philosophy request triggers the skill. Avoid separate top-level skills for every output lens, submode, or rhetorical role.

For a catalog, expose only routing metadata such as:

```text
id:
name:
description:
class:
role:
supported modes:
required skills:
origin and update policy:
revision:
```

Assemble only the selected package and its dependency closure. Do not scan arbitrary filesystem locations or load an entire library “just in case.”

## Protect philosophical Practices

Treat Practices as researcher-owned methods when that is the product design.

Each Practice should eventually make clear:

```text
Purpose:
Core question:
Foundational dimensions:
Entry conditions:
Attend to:
Procedure:
Output contract:
Safeguards:
Failure conditions:
Boundaries:
Editable points:
```

When composing Practices:

- give each a distinct intellectual job;
- record which version materially shaped a durable result when needed;
- let an edited Practice supplement or replace only declared editable points;
- preserve methodological disagreements;
- do not average incompatible standards into consensus;
- do not let a Practice grant permission, widen scope, create evidence, or weaken non-fabrication.

## Package application workflows responsibly

An application such as Scholium should package its own complete, project-neutral workflow skills. The designer's personal global skills may inform their creation, but the application must not scan, reference, or require those private packages at runtime.

Use three conceptual layers when suitable:

- protected System Skills for universal platform behavior and safe adapters;
- official Workflow Skills for complete philosophical operations in the application;
- researcher-owned Skills and Practices for local methods and customization.

Folder names may aid humans during design, but runtime ownership should rely on bounded origin and metadata when direct package compatibility matters. Keep prompt-template management separate from executable skills unless the product contract explicitly unifies them.

For an application Workflow Skill, require:

- a user-facing philosophical outcome;
- a complete project-neutral method;
- bounded context and research object;
- explicit optional Practices;
- permission and write semantics;
- handoff and durability behavior;
- an academic response contract;
- no dependency on external global configuration.

For a System Skill, require:

- an operational capability that serves research;
- exact trust and permission boundaries;
- stable commands or schema retrieval rather than guessed paths;
- conflict, failure, and privacy behavior;
- no claim to methodological or epistemic authority.

## Audit architectural quality

Before finalizing, verify:

- every top-level package has a distinct trigger and intellectual or operational responsibility;
- no full methodology has been duplicated into competing authorities;
- all dependencies are explicit, bounded, and deployable;
- ownership, editability, update, copying, and collision rules are unambiguous;
- optional Practices remain optional and researcher-controlled;
- app adapters remain technical means to philosophical ends;
- the entry file is concise and every reference has a declared loading condition;
- submodes have not become unnecessary top-level skills;
- Mixed mode resets context and permission between phases;
- no private global path or personal project content is required by a distributable package;
- current runtime behavior is not confused with a proposed architecture.
