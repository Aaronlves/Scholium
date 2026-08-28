# Scholium Completion

Use this reference immediately before Result composition, Discussion Finish,
Continue, End, or recovery of any of those operations.

## Run completion

Finish Analyze, Synthesize, Write, Critique, or Check Fidelity with
`agent submit-result` after applying the selected Method's own checks. Finish
Discuss instead with `agent finish-discussion` after the final durable Agent
turn; Discuss accepts no generic Result body. Analyze performs its bounded
fidelity self-check inside the Analyze Method; it does not create a Check
Fidelity child Run. Check Fidelity is a separate read-only Action and is
prepared only when the researcher explicitly initiates it.

Confirmed Target changes require Result finalization. Unknown writes,
conflicts, and recovery duties block End until they are determined. Use
`agent continue` only for a distinct next Action. Use `agent end` only to stop
an unfinished Run without a Result or confirmed changes; a finalized Result
needs no extra end operation. An uncertain Finish or End outcome is not a
generic retry: reload or follow the exact returned recovery instruction. The
CLI removes only an expired local credential; Continue remains bounded by the
Application-issued Session expiry.

## Result composition

Before composing an Action's submission, read exactly one protected reference
for the current Action:

- Analyze: `references/analyze-result.md`
- Synthesize: `references/synthesize-result.md`
- Write: `references/write-result.md`
- Critique: `references/critique-result.md`
- Check Fidelity: `references/check-fidelity-result.md`
- Discuss: `references/discuss-result.md`

These references govern how scholarly work is partitioned into the frozen
application contract; they do not supply or alter the intellectual Method.
The frozen Result Contract remains authoritative for which fields exist, their
types, choices, and requirement level. A customized Profile is never replaced
by a bundled default field.

Compose academic content in the Action's appropriate scholarly genre. Preserve
the question, claim, reasons, inferential or interpretive structure, material
qualification, and unresolved pressure that make the result useful. Do not turn
Method stages, lenses, evidence inventories, form fields, or operations into a
technical report or a mandatory sequence of headings. Structured declarations
remain compact supplements to one coherent philosophical outcome.

For every non-Discuss Action, return a concise one-line Record Title and the
frozen academic Result Contract, including an explicit blocked result when
required research cannot be completed safely or faithfully. Put one academic
judgment in one field. Do not recopy the Target, repeat one judgment under
several labels, or include Application-owned facts such as changed-document
lists, source routes, fingerprints, hashes, tool availability, commands, or
Run and Session mechanics. Optional fields are omitted unless the research
supports distinct content. The Record Title names the completed Record; it is
not a second result, source title, or process narration. Scholium already
attributes the Result, so do not add first-person process testimony merely to
establish attribution. Discuss instead follows its routed System Protocol and
has no generic Result submission.
