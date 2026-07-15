# Beta Skill Architecture Evidence

**Recorded:** 2026-07-15  
**Status:** Structural implementation verified; Beta release acceptance remains open.  
**Scope:** Stateless workflow contracts, bounded Skill and Practice resolution,
external-agent CLI assembly, Dialogue response transport, workspace bootstrap,
and the optional Zotero MCP boundary.

This is an evidence ledger, not a product contract and not a release approval.
It records only what the current working tree has demonstrated. Structural
validation does not certify philosophical truth, methodological adequacy, or the
researcher's permission basis.

## Implemented boundary

- Versioned ordinary and Mixed workflow contracts validate original and
  phase-local read/write boundaries, exact direct-edit targets and
  fingerprints, permission reset, provisional handoffs, Research Unit scope
  changes, package modes, dependency closure, and Practice conflicts.
- The stateless audit planner deduplicates only matching final target
  fingerprints, audit scopes, and evidence revisions, and prevents an audit
  phase from recursively scheduling itself.
- Catalog schema 2, origin-owned package class/update policy, protected-ID
  collision handling, legacy local-package defaults, complete package
  duplication, direct-package discovery, and bounded Practice-resource loading
  are implemented.
- Workflow validation, assembly, and audit planning are exposed through the
  agent-facing CLI. Contracts remain ephemeral and are not written to Dialogue
  or Application Support.
- Known app routes such as Critique use the typed assembler. Dialogue still
  records scholarly Comments and Responses rather than technical workflow
  records.
- Workspace bootstrap remains candidate-only. The external agent promotion,
  read-back, and temporary-candidate cleanup sequence is covered in a
  disposable workspace.
- `Skills/` remains canonical and is mirrored byte-for-byte into
  `ScholiumCore/Resources/Skills` for SwiftPM bundling.

## Automated evidence

| Check | Result | Limit |
| --- | --- | --- |
| Complete repository verification | `verify.sh` passed on 2026-07-15: 16 protected packages and their references validated; canonical Skill mirror equality passed; editor and deterministic 800-note RDF-1 checks passed; 345 Swift tests in 35 suites passed; workflow CLI verification passed; Release build completed. | Build and contract evidence only; this is not a packaged Release-app gate. |
| Focused architecture suites | 52 tests in 5 suites passed for catalog/resource resolution, local routing and dependencies, workflow contracts, audit planning, bootstrap, and Zotero transport boundaries. | Does not judge philosophical output. |
| Dialogue transport and Zotero regressions | 10 tests in 2 focused suites passed after adding deterministic request-scoped Dialogue rendering and Zotero 9 group-library decoding. | The current XCUITest host did not complete the new response-module interaction test. |
| Resource boundary | `diff -qr Skills ScholiumCore/Resources/Skills` is empty, and the verifier rejects missing protected references. | Release versions remain `draft` or `template` until every Beta gate passes. |
| Persistence boundary | Contract tests verify that workflow contracts and assembled instructions are not persisted as Dialogue or AI-operation history. | The external agent remains responsible for semantic routing and execution. |

The focused Settings and Critique journeys passed on disposable Triptychs during
this implementation pass. A new Dialogue journey for multi-selected response
modules is checked in, but its latest retained run failed before the test body
because macOS did not load the QA application's accessibility hierarchy. The
result is retained at
`/tmp/Scholium-UITests/Logs/Test/Test-ScholiumUITests-2026.07.15_18-24-09-+0800.xcresult`.
The deterministic Core transport test covers the exact copied request snapshot,
selected module IDs, concise response setting, preservation mode, and retrieval
command; UI interaction acceptance remains open.

## Real Zotero transport evidence

The optional MCP boundary was exercised against a running Zotero 9.0.6 local
service without retaining private library values:

1. the MCP initialize lifecycle completed;
2. bounded search and exact-item inspection completed;
3. attachment pointers were returned only after the explicit inspection flag;
4. Zotero 9's nested group-library representation was decoded without changing
   the bounded request policy; and
5. unavailable or ambiguous states remained explicit rather than guessed.

The guarded import path was exercised with one synthetic BibTeX record in an
isolated temporary Zotero profile and data directory. The service performed a
dry run, issued a target-bound one-shot authorization, imported only after
explicit confirmation, read the item back through the local API, and disposed
of the temporary profile and data. The ordinary Zotero profile was reopened and
verified afterward. No import was made into the live research library, and no
private source text or bibliographic values are retained here.

## Required philosophical field trials

The ten trials in
[`Skills/evals/REAL_WORKFLOW_ASSESSMENT.md`](../Skills/evals/REAL_WORKFLOW_ASSESSMENT.md)
remain acceptance work. Automated fixtures prove routing and safety properties;
they cannot establish that an external agent produced philosophically adequate
work.

| Trial | Current status |
| --- | --- |
| Complete three-pass source analysis | Pending semantic field execution and researcher verdict. |
| Partial-source analysis without whole-source overclaiming | Pending semantic field execution and researcher verdict. |
| Continued long-book analysis in one cumulative Analysis | Pending semantic field execution and researcher verdict. |
| Same-debate importance calibration across at least ten Analyses | Pending semantic field execution and researcher verdict. |
| Source-to-note integration with an exact evidential role | Pending semantic field execution and researcher verdict. |
| Dialogue-to-note integration only after researcher settlement | Pending semantic field execution and researcher verdict. |
| Argument development, authorized Work revision, one final audit, and independent Critique | Pending semantic field execution and researcher verdict. |
| APA starter followed by a non-APA Researcher Skill | Pending semantic field execution and researcher verdict. |
| Unavailable Zotero transport with an explicit stop | Structural failure handling passes; end-to-end field verdict remains pending. |
| Conflicting edited Practices without silent resolution | Structural conflict fixture passes; philosophical field verdict remains pending. |

## Manual acceptance still required

- Dialogue response-module selection and concise-output presentation in the
  running app;
- Settings ownership, collision recovery, and complete-package duplication as
  a researcher journey;
- Critique routing as part of the complete Mixed workflow;
- keyboard-only operation, Full Keyboard Access, VoiceOver, Voice Control,
  contrast, Reduce Transparency, Reduce Motion, and 200% text review; and
- researcher evaluation of fidelity, conceptual precision, argumentative
  quality, and usefulness across the ten field trials.

## Release decision

G10 and J-014 through J-016 remain open. Package versions therefore remain
`draft` or `template`; no Beta release-candidate promotion, packaging,
publication, or release claim is authorized by this record.

`Docs/PROPOSED_SKILL_ARCHITECTURE.md` is not present in the active checkout or
tracked history. This pass did not reconstruct a substitute and thereby invent
a design authority. The adopted Product Guide and PRD contain the active target;
if the proposal document is restored from an external design archive, its
current-versus-target section should be reconciled before final Beta approval.
