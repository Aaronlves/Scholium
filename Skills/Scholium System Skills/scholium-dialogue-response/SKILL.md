---
name: scholium-dialogue-response
description: Interpret and honor the researcher-selected response contract attached to a Scholium Dialogue request. Use whenever work originates from a copied Scholium Dialogue instruction or includes a Dialogue ID, especially when the researcher selected one or more response modules, a concision level, or a Comment-preservation mode. Compose the requested scholarly Response and persist it through the Scholium Dialogue CLI without turning the selection into philosophical method, file-edit permission, or settled knowledge.
---

# Scholium Dialogue Response

Apply `scholium-core-protocol`. Treat this protected System Skill as the response contract between the Scholia panel and the agent. It controls how to present and record the result; it does not perform the philosophical workflow, authorize note edits, or decide what the researcher accepts.

## Resolve the request contract

1. Identify the exact Triptych selector and Dialogue ID supplied by Scholium.
2. Read [references/response-contract.md](references/response-contract.md) completely.
3. Retrieve the Dialogue with `scholium dialogue show <dialogue-id> --triptych <triptych> --format json` through `scholium-research-integration`.
4. Use the request-scoped `responseContract` snapshot when present. Do not replace it with a newer workspace default.
5. If the snapshot is absent, apply the legacy fallback in the contract reference and state that the exact request-time choice was unavailable.
6. Read [references/response-method.md](references/response-method.md) and compose only the base outcome plus the selected modules.

The portable default profile is located exactly at:

```text
<Works parent>/.scholium/dialogue-response.json
```

For a Works vault at `/Research/Ethics/Works`, the file is `/Research/Ethics/.scholium/dialogue-response.json`. This profile is app-managed and read-only to agents. It is a default, not authoritative evidence of what was selected for an earlier Dialogue.

## Establish the response packet

```text
Triptych selector:
Dialogue ID:
Contract source: request-snapshot | legacy-profile | legacy-default
Profile revision, if available:
Base response: academic-outcome
Selected modules:
Comment preservation:
Concision: concise
Agent name:
Dialogue target: overall | selected-note | selected-comment
Work result and durability:
Material actually checked:
Uncertainty and limitations:
Researcher decision needed:
```

Do not infer a response module from the workflow, a selected Practice, or the content of the answer. Do not treat a response selection as permission to retrieve additional materials or perform additional philosophical analysis.

## Compose the Response

- Always give one concise **Academic Outcome**. If notes changed, describe the academic change; otherwise state the scholarly result.
- Add only the modules selected in the request snapshot.
- Preserve source limitations, uncertainty, conflicts, failed writes, and required researcher decisions even when no optional module requests them.
- Keep each selected module to one short paragraph or at most three nonduplicative items.
- Omit a module that has no warranted content rather than fabricating significance, criticism, background, or research directions. Say briefly why it could not be supplied when the omission matters.
- Keep routine commands, files, line counts, model details, and implementation logs secondary unless they explain a failure or integrity risk.
- Distinguish an agent proposal or evaluation from a researcher-settled conclusion.
- Match the researcher’s language unless the instruction requests another language.

## Persist the Response

Use `scholium-research-integration` to record exactly one final Response:

```sh
scholium dialogue reply <dialogue-id> \
  --triptych <triptych> \
  --agent <agent-name> \
  --from <response-file>
```

Add an exact note or Comment selector only when the Response is specifically addressed to that target. Do not edit the Dialogue store or the portable response-profile file directly.

If work stops, persist a concise stopped-state Response when the Dialogue remains writable. Identify the academic consequence, the blocker, and any researcher decision needed.

## Preserve boundaries

- A response contract controls presentation and persistence, not task scope, evidence, method, or write authorization.
- A selected module does not require the agent to invent content to fill a heading.
- A profile change after Dialogue creation does not retroactively change that Dialogue.
- An agent Response remains an attributed contribution to Dialogue; it does not settle the note.
- Comment condensation changes presentation only. Never label condensed text as a verbatim researcher Comment.
- Unknown contract versions or module IDs must remain visible. Apply known mandatory integrity rules, report the unsupported item, and do not silently substitute another module.
