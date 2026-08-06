# Authenticated Agent transport

Use this reference only for a Scholium-prepared Research Run. The App routes
the Run's one current Method and Practices; there is no generic package catalog
or workflow assembler for the Agent to select another method.

## Confirm the local boundary

```sh
scholium version --format json
scholium doctor --format json
```

Use `scholium help <command> <subcommand>` or command-specific `--help` rather
than remembered Beta syntax. If the installed CLI lacks a required Agent
command, report the limitation. Never guess options or edit `.scholium` state.

## Pair and recover the Run

The App supplies an opaque Run locator and a one-use Pairing Code. Start:

```sh
scholium agent pair --run <run-locator>
```

Read the code from the researcher's copied Scholium handoff, paste it on
standard input, and send EOF. Do not move it into argv, a URL, file, another
prompt, feedback, or log. The CLI stores the hidden Session credential in
current-user-only local state and never prints it. Pairing is local, short
lived, revocable, and invalid after App restart.

```sh
scholium agent context --run <run-locator>
scholium agent reload --run <run-locator>
```

The authenticated response supplies the Run Brief, Core Protocol on first
delivery, exact Method, Practices, optional local folder path, capabilities,
Result Contract, current bounded write-set view, and any explicit continuation
handoff. Reload recovers current authority but does not replay earlier Research
Context responses.

## Research and write

Use strict JSON from a file or standard input:

```sh
scholium agent query --run <run-locator> --from <query.json|->
scholium agent extend-write-set --run <run-locator> --from <intent.json|->
scholium agent write --run <run-locator> --from <write.json|->
scholium agent resolve-write-conflict --run <run-locator> --from <resolution.json|->
```

Research Context preserves source identity, actor attribution, revision,
locator, scope, currentness, retrieval reason, and limitations. It cannot
change Method or authority. Only current write-set entries are writable. Each
write is independently revision checked, checkpointed, saved, read back, and
recoverable. After `refresh_authority`, reread and reconsider changed source
before retrying; `abandon_write` closes only that attempt.

## Result and continuation

```sh
scholium agent submit-result --run <run-locator> --from <result.json|->
scholium agent continue --run <run-locator> --from <continuation.json|->
scholium agent end --run <run-locator>
```

Submit exactly the frozen Result Contract, including `blocked` when needed.
Selection or retrieval does not establish source use. Continue Research is a
request for a fresh independent Run with a bounded, epistemically labeled
handoff; it carries no prior response, cache, capability, or write authority.
Use `end` only to stop an unfinished Run without a Result. It revokes new
Agent operations while retaining confirmed changes, conflicts, and recovery.

## Separately paired Method improvement

A researcher may explicitly start a new Method-improvement Run from one saved
Record feedback comment. Pair its fresh locator/code in the same hidden-input
boundary, then use:

```sh
scholium agent method-context --run <run-locator>
scholium agent improve-method --run <run-locator> --from <draft.json|->
scholium agent end --run <run-locator>
```

`method-context` freezes the exact feedback, finalized Result fingerprint,
primary Method, and linked Practices. `improve-method` may replace one returned
target or save an accurate `diagnosed_no_change`/`unavailable` outcome. The CLI
fills machine revisions from authenticated context. Scholium grants no ordinary
Result or Bounded Write Set authority, clears only unchanged feedback, and
retains one local terminal receipt rather than a feedback history.

There is no current `scholium skills`, `scholium workflow`, or
`scholium action complete` route. Successful transport or persistence is not
evidence that the philosophical method was adequate.
