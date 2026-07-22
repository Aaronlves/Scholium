---
name: scholium-discuss-response
description: Interpret and honor the researcher-selected response contract attached to a Scholium Discuss request. Use whenever work originates from a copied Scholium Discuss instruction or includes a Discussion ID, especially when the researcher selected one or more response modules, a concision level, or a Comment-preservation mode. Compose the requested scholarly Response and persist it through the Scholium Discuss CLI without turning the selection into philosophical method, file-edit permission, or settled knowledge.
---

# Scholium Discuss Response

Apply `scholium-core-protocol`. Treat this protected System Skill as the response contract between Scholium Actions and the agent. It controls how to present and record the result; it does not perform the philosophical workflow, authorize note edits, or decide what the researcher accepts.

Discuss is note-nonmutating. It may read the fixed Target and selected Materials and may append an attributed Response to the Discussion. If the researcher explicitly asks to change the current Analysis or Topic, return to Work with Agent and begin a separately authorized Develop run; for a Work, begin Revise. Never treat a copied Discuss instruction, selected response module, or earlier checkpoint as note-write permission.

## Resolve the request contract

1. Identify the exact Triptych selector and Discussion ID supplied by Scholium.
2. Read [references/response-contract.md](references/response-contract.md) completely.
3. Retrieve the Discussion with `scholium discuss show <discussion-id> --triptych <triptych> --format json` through `scholium-research-integration`.
4. Require and use the request-scoped `responseContract` snapshot. Do not replace it with a newer workspace default. A missing snapshot is an invalid current Discuss record and must fail closed.
5. Read [references/response-method.md](references/response-method.md) and compose only the base outcome plus the selected modules.

The portable default profile is located exactly at:

```text
<Works parent>/.scholium/dialogue-response.json
```

For a Works vault at `/Research/Ethics/Works`, the file is `/Research/Ethics/.scholium/dialogue-response.json`. This legacy-named profile is app-managed and read-only to agents. It is a default, not authoritative evidence of what was selected for an earlier Discussion.

## Establish the response packet

```text
Triptych selector:
Discussion ID:
Contract source: request-snapshot
Profile revision, if available:
Base response: academic-outcome
Selected modules:
Comment preservation:
Concision: concise
Agent name:
Discussion target: overall | selected-note | selected-comment
Work result and durability:
Material actually checked:
Uncertainty and limitations:
Researcher decision needed:
```

Do not infer a response module from the workflow, a selected Practice, or the content of the answer. Do not treat a response selection as permission to retrieve additional materials or perform additional philosophical analysis.

## Compose the Response

- Always give one concise **Academic Outcome**. If notes changed, describe the academic change; otherwise state the scholarly result.
- Add only the modules selected in the request snapshot.
- Consider every selected module and allocate methodological effort freely according to the actual question and evidence. Do not use numerical weights, coverage ratios, or an allocation ledger.
- Preserve source limitations, uncertainty, conflicts, failed writes, and required researcher decisions even when no optional module requests them.
- Keep each selected module to one short paragraph or at most three nonduplicative items.
- Omit a module that has no warranted content rather than fabricating significance, criticism, background, or research directions. Say briefly why it could not be supplied when the omission matters.
- Keep routine commands, files, line counts, model details, and implementation logs secondary unless they explain a failure or integrity risk.
- Distinguish an agent proposal or evaluation from a researcher-settled conclusion.
- Match the researcher’s language unless the instruction requests another language.

## Persist the Response

Use `scholium-research-integration` to record exactly one final Response:

```sh
scholium discuss reply <discussion-id> \
  --triptych <triptych> \
  --agent <agent-name> \
  --from <response-file>
```

Add an exact note or Comment selector only when the Response is specifically addressed to that target. Do not edit the compatibility store or the portable response-profile file directly.

If work stops, persist a concise stopped-state Response when the Discussion remains writable. Identify the academic consequence, the blocker, and any researcher decision needed.

## Preserve boundaries

- A response contract controls presentation and persistence, not task scope, evidence, method, or write authorization.
- A selected module must receive genuine consideration, but only materially useful and warranted findings appear. Returning no finding is valid; silently skipping a selected module or inventing content to fill a heading is not.
- A profile change after Discussion creation does not retroactively change that Discussion.
- An agent Response remains an attributed contribution to Discussion; it does not settle the note.
- Comment condensation changes presentation only. Never label condensed text as a verbatim researcher Comment.
- Unknown contract versions or module IDs must remain visible. Apply known mandatory integrity rules, report the unsupported item, and do not silently substitute another module.
