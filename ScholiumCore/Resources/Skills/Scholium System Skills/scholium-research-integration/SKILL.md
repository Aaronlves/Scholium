---
name: scholium-research-integration
description: Operate on a configured Scholium Triptych through the protected Scholium CLI contract. Use whenever an agent must discover the researcher-selected Analyses, Topics, or Works locations; inspect the workspace catalog; read an exact note revision; create or replace an authorized note; integrate verified source material or a researcher-settled Discussion result; declare or revise a role-aware Research Unit; fill only needed researcher-facing properties; or persist a response composed under scholium-discuss-response. Apply with the Core Protocol and the relevant philosophical Workflow Skill.
---

# Scholium Research Integration

Apply `scholium-core-protocol`. Treat this protected package as the application adapter between philosophical workflows and the researcher's configured Triptych. It defines how to access and mutate Scholium; it does not decide philosophical method or grant permission.

## Select the operation

Choose the narrowest operation:

- `read-only-context` — discover the Triptych and retrieve only the notes, relations, comments, or Discussion needed by the active workflow;
- `source-to-note` — incorporate verified source material into exact notes with an explicit evidential role;
- `discussion-to-note` — incorporate only a researcher-settled conclusion from Discuss into exact notes;
- `authorized-workflow-edit` — persist an exact edit already justified by the active writing, development, synthesis, feedback, or other Workflow Skill.

Do not convert retrieval, a handoff, or a useful agent proposal into write permission.

## Establish the integration packet

```text
Operation:
Active Workflow Skill:
Triptych selector:
Discussion ID: none | UUID
Response contract source: none | request-snapshot
Input and evidential status:
Exact read set:
Exact write set:
Research Unit change: none | absent -> declared | old -> new
Permitted property keys:
Permission: read-only | candidate-only | direct-edit-authorized
Expected note fingerprints:
Output:
Stop condition:
Durability:
Audit state:
```

The write set must name every note. Include `research_unit` or another
researcher-owned property in the write set before changing it. Creation and
modification time are never agent-permitted property keys; protected-machine
properties require their own exact authorization and current fingerprint.

## Load the required references

Always read [references/cli-contract.md](references/cli-contract.md) before accessing a live Triptych.

Additionally:

- read [references/integration-method.md](references/integration-method.md) for `source-to-note` or `discussion-to-note`;
- read [references/properties.md](references/properties.md) before creating a note or changing Properties or Research Unit.
- load `scholium-discuss-response` when a Discussion ID is present; let it interpret the request-scoped response contract and compose the scholarly Response before this adapter persists it.

## Execute safely

1. Resolve the selected Triptych through Scholium rather than guessing paths from folder names.
2. Retrieve the smallest sufficient catalog, note, comment, relation, or Discussion context.
3. For a prepared Research Function, recover its exact state with `function show` and prefer its typed `nextActions`; do not reconstruct continuation commands from prose.
4. Read every existing write target with `--format json` and retain its SHA-256 fingerprint.
5. Apply the active Workflow Skill's method while preserving evidential layers and unrelated Markdown or YAML.
6. Recheck the exact write set, role-aware Research Unit, property ownership, permitted keys, and direct-edit authorization.
7. Write through the Scholium CLI using the expected fingerprint; stop on any revision mismatch.
8. Reread the changed note and record its new fingerprint.
9. Mark substantive philosophical changes for one version-bound content audit. Use the returned `prepare_fidelity` action; do not manually reconstruct the child request.
10. When a Discussion ID is present, use `scholium-discuss-response` to compose the base academic outcome and selected response modules, then persist exactly one final Response through the CLI after completing or stopping the work.

## Preserve the boundary

- Do not edit `.scholium` machine state directly.
- Do not derive philosophical support from a link, folder, tag, or property alone.
- Do not fill an unknown property value merely to complete a profile.
- Do not infer a Research Unit from folder location, keywords, links, or prose length, and do not expand a note beyond its declared Research Unit without an authorized property change.
- Do not add or maintain `created`, `updated`, `modified`, or equivalent timestamp properties; creation and modification time are owned by Scholium History.
- Do not create or change `status`; it has no Scholium property semantics.
- Do not treat an agent Response as a researcher-settled conclusion.
- Do not infer response modules from the workflow or substitute the current portable profile for a request-scoped Discuss snapshot.
- Do not claim a write succeeded until the CLI confirms it and the resulting note can be reread.

## Return

Report the academic result, exact notes changed, authorized property changes,
unresolved evidence, audit state, and final durability. Keep CLI details
secondary unless a command, conflict, or revision check prevented completion.
