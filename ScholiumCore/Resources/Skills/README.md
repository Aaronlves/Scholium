# Scholium Product Skill Packages

> **Status:** Active product sources. Skills is canonical and ScholiumCore/Resources/Skills is a generated mirror. Run Tools/Scripts/sync-product-skills.sh with --sync or --check; never edit the mirror independently.

These are philosophy-facing research packages, not development-agent skills. They pursue warranted philosophical results, preserve source and researcher fidelity, and support a precise, reviewable knowledge base. Technical adapters remain subordinate to that purpose.

## Ownership

- System Skills are protected, bundled, and release-managed.
- Workflow Skills are official and release-managed. A researcher may duplicate one into an independent Triptych-local Researcher Skill.
- Researcher Skills and Practices are editable after adoption and are never overwritten by a release.

Runtime discovery is bounded to the release catalog plus direct packages under .scholium/skills/<skill-id>/. Scholium does not scan global Codex or plugin directories and does not infer capability from filenames.

## Package map

System:

- scholium-core-protocol: universal integrity and phase isolation;
- scholium-research-integration: bounded Triptych reads, writes, and records;
- scholium-dialogue-response: read-only-by-default Dialogue transport and response persistence;
- scholium-zotero-integration: bounded optional library transport.

Workflow — exactly five:

- scholium-development: Develop an Analysis or Topic. Exploration, concept work, argument work, synthesis, and expression are conditional methods chosen by the agent from the real burden.
- scholium-critique: assess an exact Work or passage read-only and write a separate Critique.
- scholium-revision: revise the current Work, including explicit received-feedback disposition.
- scholium-content-fidelity: run revision-bound Content checks and coordinate optional bound Citations checks read-only.
- scholium-manuscript: coordinate the smallest declared plan of isolated Revise, Fidelity, and optional Critique phases while the current Work remains the only document Target.

Researcher:

- scholium-philosophical-practices: optional editable Practice overlays;
- scholium-source-analyzer: complete optional method for an external agent to analyze papers, books, chapters, and other philosophically relevant sources without invoking a Scholium Research Function;
- scholium-prose-control: optional meaning-preserving method for Revise;
- scholium-citation-verification: optional APA 7 verification and formatting starter for Fidelity.

Dialogue is System transport and record infrastructure. Human Review is a researcher action and has no skill. Source Analyzer is a shipped Researcher Skill, but Source Analysis and skill self-evolution are not Workflow packages or Research Strip functions. The agent may analyze a source supplied through Zotero, a local file, or another available channel; Scholium need not store or control the source. Persisting or developing the result in a Scholium note is a separate researcher-authorized action.

## Function routing

Catalog supported_functions binds packages to semantic Research Function IDs. The visible function selects a function, never a package ID or internal method. Application resolves one eligible package, its dependency closure, explicit Triptych bindings, and only the conditional resources needed for the run.

Legacy supported_modes remains for older records and internal method compatibility. It is not interface language or write permission. A one-click run with conditional methods first produces a read-only preflight containing the complete primary method. After inspecting the real work, the external agent finalizes an explicit semantic selection—including an empty selection when the primary method is sufficient—through the function API. The same run then records whole-package revisions and the exact conditional resources attached to its immutable execution packet.

Function boundaries:

- Develop: Analysis or Topic Target; Materials read-only.
- Critique: Work Target read-only; separate Critique writable.
- Revise: current Work Target only writable; Materials read-only.
- Fidelity: every Target role read-only; Content always available, Citations capability-bound.
- Manuscript: current Work Target only; every phase independently prepared.

Dialogue is read-only unless an explicit note-changing request is promoted through the function API to Develop or Revise. Write-capable functions require a Before Agent Work checkpoint and end with a pending revision-specific Fidelity handoff. Scholium has no embedded agent runtime, so awaiting or missing Fidelity must never be presented as an automatic audit.

## Capability and citation bindings

Catalog capabilities describes declared behavior, not philosophical authority. Citation packages additionally declare citation_styles and an explicit citation_style_resources mapping. The included APA starter declares:

- supported_functions: fidelity
- capabilities: citation-verification and citation-formatting
- citation_styles: apa-7
- citation_style_resources: apa-7 to references/apa-7-starter.md

Application determines whether a bundled template is available, a valid Triptych-local package exists, an explicit package-and-style binding is active, or a binding is malformed or missing. Core validates the selected semantic style against the local package and loads its declared resource rather than guessing from a filename. A missing or mismatched style disables the Citations route with a typed repair reason. The APA starter never silently answers Chicago, MLA, Oxford, MHRA, legal, ancient-text, journal-house, or unspecified-style requests.

## Selective assembly

An ordinary run contains:

1. scholium-core-protocol;
2. one primary Workflow package, except Dialogue and Human Review;
3. the research-integration or Dialogue System adapters required by the operation;
4. only explicitly selected Researcher Skills or Practices;
5. only conditional resources actually needed.

Manuscript is an orchestrator. It declares only the role-valid Work phases actually warranted from Revise, Fidelity, and optional Critique; it does not impose one universal sequence, depend on, or concatenate every Workflow package. Application resolves each needed phase independently, resets Target and Material fingerprints, evidence, permission, and write scope, and preserves a labeled handoff. Conceptual or argumentative development of the Work occurs inside Revise; Develop remains Analysis/Topic-only and never creates a second Target.

## Researcher-skill evolution

Self-evolution is Research Guidance maintenance, not a Strip function and never an automatic consequence of research work. Only an opted-in Triptych-local Researcher Skill may be evolved. Bundled System and Workflow packages are immutable.

A maintenance transaction requires the expected whole-package revision, a bounded replacement containing SKILL.md plus optional one-level references, templates, and evals, successful structural evaluation, and an explicit confirmation token. Core snapshots the complete old package, replaces atomically, reads back and fingerprints the new package, and can restore the snapshot. Failure leaves or restores the earlier package; partial packages never become visible.

## Evidence and evaluation

catalog.yaml owns IDs, ownership, function compatibility, legacy modes, capabilities, citation styles, dependencies, and update policy. Each package owns its method and conditional resources. evals/cases.yaml covers positive, boundary, and adversarial function behavior; evals/REAL_WORKFLOW_ASSESSMENT.md defines field acceptance.

Repository and catalog tests prove packaging, routing, containment, revisions, and transaction behavior. They do not prove philosophical truth or that an external agent complied with every method. Field trials must inspect the actual output, evidence use, write set, and reported uncertainty.

## Universal standard

Pursue the best warranted philosophical result available under the actual evidence. Maintain fidelity, precision, accuracy, non-fabrication, privacy, and researcher authority. Keep source material, interpretation, reconstruction, evaluation, agent proposal, researcher commitment, and durable settlement distinct. Missing evidence narrows or stops the result; it never licenses invention.
