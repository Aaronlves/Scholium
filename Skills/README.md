# Scholium Product Skill Packages

> **Status:** Active Beta product sources bundled as ScholiumCore resources. `Skills/` is the canonical source and is mirrored into `ScholiumCore/Resources/Skills`; the CLI exposes bounded catalog, package resource, assembly, bootstrap, and external Zotero transport descriptors.

This directory is the canonical design source for skills Scholium may ship to researchers. It is distinct from root `AGENTS.md` and `.agents/skills`, which guide agents that design and build Scholium itself.

These packages are philosophy-facing research Skills, not Skills for coding or maintaining the Scholium application. They pursue warranted philosophical understanding, care for source and researcher fidelity, and help construct a precise, reviewable research knowledge base. System adapters may describe CLI, file, or MCP operations, but those operations remain subordinate mechanisms rather than the intellectual purpose or primary reported result.

The ownership folders are repository organization only. Runtime packages retain the direct identity `<skill-id>/SKILL.md`; nested ownership folders are not required in a Triptych or app bundle.

## Package groups

```text
Scholium System Skills/
├── scholium-core-protocol/
├── scholium-research-integration/
├── scholium-dialogue-response/
└── scholium-zotero-integration/

Scholium Workflow Skills/
├── scholium-research-exploration/
├── scholium-source-analysis/
├── scholium-philosophical-development/
├── scholium-philosophical-review/
├── scholium-philosophical-writing/
├── scholium-research-synthesis/
├── scholium-feedback-processing/
├── scholium-content-audit/
└── scholium-manuscript-workflow/

Researcher Skills/
├── scholium-philosophical-practices/
│   └── Researcher-owned editable Practice template
├── scholium-prose-control/
│   └── Researcher-owned editable academic-prose method
└── scholium-citation-verification/
    └── Researcher-owned editable APA 7 starter
```

Mixed mode is part of `scholium-core-protocol`; it is orchestration rather than a philosophical workflow. Scholium provides no protected universal citation-format method. It does provide an optional editable APA 7 citation-verification starter as a Researcher Skill template; researchers may adopt, modify, replace, or ignore it for other styles, languages, editions, and bibliographic tools.

## Ownership

- **System Skills** are protected, bundled, and release-managed.
- **Workflow Skills** are official and release-managed. A researcher may duplicate one into an independent Researcher Skill.
- **Researcher Skills and Practices** are editable and never overwritten by a Scholium release.

Each official Workflow Skill contains a complete project-neutral base method. It does not depend on a personal skill library, a global Codex skill directory, or private workspace paths.

Every Workflow Skill also declares compatible researcher-owned Philosophical Practices. Practices are optional overlays, not dependencies: the official workflow remains complete on its own, and only Practices explicitly selected by the current task or an active Researcher Skill are loaded. Their stable IDs and revisions are recorded, and methodological conflicts remain visible for researcher judgment.

Workflow packages may include release-pinned references and templates. Duplicating an official package copies its complete bounded package under a new Researcher Skill ID; the copy's references, templates, and package revision are independent of later releases. `scholium-source-analysis` requires distinct Orientation, Analytical, and Review passes over the complete analysis unit and contains one project-neutral family of thorough, concise, and provisional report templates. Existing target schemas and custom fields remain authoritative, but Scholium ships no researcher- or project-specific compatibility schema.

Durable notes may declare a minimal Research Unit, presented by the app as **Research Status**. The bundled contract contains only required `research_unit.scope` and optional `research_unit.limitations`. A new durable Analysis requires it; Topic and Work declarations remain optional; Dialogue uses its app-owned target context rather than YAML. For a long source, the default is one continuously maintained source-level Analysis whose scope expands only after each bounded session unit completes the three-pass method. Creation and modification time are app-owned History data, never agent-filled properties.

`scholium-philosophical-writing` owns planning, drafting, substantive revision, write-mode permission, and durability. Meaning-preserving prose revision is separate: the optional copy-on-adoption `scholium-prose-control` Researcher Skill owns its preservation ledger and editable academic-style profile. It is selected alongside Philosophical Writing, never activates automatically, and may expose but must not silently repair a philosophical defect.

## Runtime assembly target

For one ordinary task, assemble:

```text
scholium-core-protocol
        +
one primary Workflow Skill
        +
scholium-research-integration when live Triptych or Dialogue access is needed
        +
scholium-dialogue-response when the task originates in Dialogue
        +
scholium-zotero-integration when a configured Zotero MCP capability is needed
        +
only explicitly selected Researcher Skills or Practices
```

`scholium-dialogue-response` reads the request-scoped response selection captured by Scholium, composes only the selected scholarly response modules, and delegates persistence to `scholium-research-integration`. Its target portable default profile is `<Works parent>/.scholium/dialogue-response.json`; each Dialogue must snapshot the effective choice so later preference changes do not alter an earlier request.

For a complex task, the Core Protocol sequences ordinary modes through its Mixed-mode reference and resets context, permission, and assumptions between phases.

`scholium-manuscript-workflow` is the one official end-to-end coordinator. It selects and sequences the complete ordinary workflows without restating them, keeps evidence state separate from readiness judgment, and can conclude only that a version is **ready for researcher submission decision**.

Catalog `supported_modes` declares compatibility; `automatic_modes` separately declares which protected System packages enter an ordinary assembly without an explicit ID. Core is always automatic, Dialogue is automatic only for Dialogue mode, and live Triptych or Zotero adapters are otherwise selected when the task needs them.

The Zotero System Skill is an instruction contract, not an MCP transport. Its supported source installation path uses the first-party `scholium zotero mcp serve` CLI service. Retrieval is the default; imports require an exact current-task request, target-bound one-shot dry-run authorization, explicit tool confirmation, and read-back verification. The adapter never treats Zotero metadata as evidence for a philosophical claim and never reads or writes the live Zotero database directly.

The Beta routing and version descriptors are in [`catalog.yaml`](catalog.yaml). Forward-test fixtures are in [`evals/cases.yaml`](evals/cases.yaml), and the end-to-end field-test boundary is documented in [`evals/REAL_WORKFLOW_ASSESSMENT.md`](evals/REAL_WORKFLOW_ASSESSMENT.md).

`Package.swift` copies the synchronized `ScholiumCore/Resources/Skills` snapshot into `ScholiumCore`, and the typed loader reads that snapshot. Keep the two trees byte-identical. Building or packaging a release remains a separate, explicitly verified step.

## Architecture and evidence boundary

This README is the concise architecture authority for the bundled Beta
packages. `catalog.yaml` owns package IDs, ownership, routing, modes, and
dependencies; each package owns its method and resource contracts; `evals/`
owns forward and field acceptance; [the PRD](../Docs/PRD.md) owns release
requirements and gates; and [Implementation Status](../Docs/IMPLEMENTATION_STATUS.md)
owns current reachability and verification. None of those sources turns a
target into implemented behavior by implication.

Scholium owns bounded discovery, package validation, dependency closure,
permissions, and task facts. The external agent owns semantic mode selection.
Core Protocol's Mixed mode makes phase, scope, handoff, and permission resets
explicit. Runtime packages remain direct `<skill-id>/SKILL.md` packages under
`.scholium/skills/`; repository ownership folders are not runtime paths, and
Scholium never scans a global skill directory.

This architecture is a Beta target and implementation boundary, not release
evidence. A package is complete only when its bounded contents and declared
resources are valid; product acceptance still requires the applicable evals,
release gates, and evidence recorded in the implementation ledger.

## Optional workspace instruction bootstrap

Scholium does not ship a second, researcher-workspace `AGENTS.md`. On an explicit setup request, `scholium-core-protocol` may load its protected [`workspace-bootstrap.md`](<Scholium System Skills/scholium-core-protocol/references/workspace-bootstrap.md>) reference so an external agent can construct a minimal researcher-owned adapter at an explicitly verified target.

The bootstrap is one-shot. After the generated file passes promotion and read-back validation, the agent deletes only a task-created temporary bootstrap copy. The bundled reference remains protected, a failed bootstrap is retained for diagnosis, and an existing applicable `AGENTS.md` is never overwritten or shadowed.

## Universal standard

Pursue the best warranted philosophical result without claiming automatic access to truth. Maintain fidelity, precision, accuracy, non-fabrication, and explicit uncertainty. Never invent or misattribute concepts, claims, arguments, objections, replies, sources, quotations, locators, or evidence. Keep source material, interpretation, reconstruction, evaluation, synthesis, agent proposal, and researcher commitment distinct. Judge completion by the academic result and its contribution to the researcher's knowledge base, not by technical activity.
