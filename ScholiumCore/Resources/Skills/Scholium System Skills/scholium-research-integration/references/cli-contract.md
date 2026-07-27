# Scholium CLI Contract

Use the `scholium` executable as the supported agent-facing boundary for configured Triptychs. Do not infer vault paths or write directly to registered research files when the CLI operation is available.

## 0. Confirm the executable and discover syntax

Before a cold-start task, confirm that the current executable is the expected
Scholium CLI and that its local configuration is usable:

```sh
scholium version --format json
scholium doctor --format json
scholium help action --format json
```

Use `scholium help <command> <subcommand>` or append `--help` to that command.
Do not rely on remembered Beta syntax. Unknown, duplicate, or valueless options
are errors; never reinterpret a failed option as if it had been applied. When a
command supports `--format json`, errors use a stable JSON envelope with `code`,
`message`, and `help`.

## 1. Discover the Triptych

List the researcher-configured Triptychs and their canonical Analyses, Topics, and Works locations:

```sh
scholium vault list
```

Use the Triptych UUID or unique name returned by Scholium as `<triptych>`. Use role selectors such as `analyses`, `topics`, and `works` as `<vault>`; do not infer a role from a directory name.

Retrieve the machine-readable note catalog when orientation is required:

```sh
scholium workspace catalog --triptych <triptych> --format json
```

Use `scholium search` or the link and graph commands only when the active workflow needs them. Do not enumerate the whole workspace by default.

## 2. Read exact note state

Read an existing note before relying on or modifying it:

```sh
scholium read <vault>:<relative-path> --format json
```

Retain:

- `vault_id` and `relative_path` as target identity;
- `content` as the exact current Markdown;
- `sha256` as the expected revision for a mutation.

A fingerprint detects stale state. It does not grant permission.

## 3. Execute prepared Research Actions

Prefer `nextActions` from JSON preparation and completion results. Each action
contains an argument-vector `command`, not a shell string. Execute the
arguments without interpolation and supply `inputTemplate` through stdin only
after replacing every `REPLACE_WITH` marker with checked evidence.
The normal lifecycle is:

```sh
scholium action available --from <target-json|-> --format json
scholium action prepare --from <request-json|-> --format json
scholium action show <run-id> --triptych <triptych> --format json
```

Current preparations attach one complete Action Method and expose no
researcher- or agent-selected conditional mode. If recovered legacy state still
asks for a secondary method or mode choice, cancel or leave that state
unchanged and prepare a fresh Action. Generic `skills show` retrieval is not
attached to a run.

Record any required Discuss reply or Critique output, perform only the
authorized write, and submit the Action-specific completion schema. An
Analyze, Synthesize, or Write completion that changed the Target returns
`awaiting_fidelity` plus a `prepare_fidelity` action. Use it instead of
constructing a Fidelity request manually:

```sh
scholium action prepare-fidelity <parent-run-id> \
  --triptych <triptych> --format json
```

Complete the returned read-only Fidelity child. Call `prepare-fidelity` again
when recovery is needed; exact existing evidence is reused and the result
provides the parent-link completion action. Use `action show` after process
loss or uncertainty. Cancellation is idempotent only before durable completion
evidence exists.

### Request a separately bounded continuation

When the live packet supplies a Triptych ID, parent run ID, and coordination
key, an agent may ask Scholium to consider additional Notes or another
write-capable Action through the local MCP service:

```sh
scholium agent mcp serve
```

Use only these advertised tools:

- `request_note_changes` submits the complete schema-v1 request supplied or
  assembled from current exact identities and revisions;
- `show_note_change_request` reads the existing request state and never creates
  a second request;
- `cancel_note_change_request` cancels an unresolved request without changing a
  Note.

Pass the coordination key only inside the MCP tool arguments over stdin. Never
place it in command-line arguments, a temporary file, shell history, logs,
feedback, or a Research Record. If the App is not running, the service returns
unavailable; do not launch it, queue the request, or bypass the route. Exact
request replay is safe, but reusing one request ID for changed content is not.
If dispatch returns `outcome_unknown`, query the same request ID before any
retry; never create a new request ID merely because the first response timed
out. The first request ID consumes that coordination key permanently; a
terminal decision does not authorize a second ID.

A pending or allowed request is coordination state, not write authority. The
parent packet remains unchanged. An allowed `request_note_changes` or
`show_note_change_request` result includes `child_preparations` only after
Scholium has independently prepared the approved children against current live
state. Each entry binds one `note_id` to one complete preparation with its own
run ID, snapshot, exact revisions, checkpoint, completion grant, and Fidelity
route. Use only that entry's instructions and authority for that Note; never
combine sibling write sets or reuse the parent's keys.

Querying the same request returns the same reserved child run IDs and does not
create another grant. A cancelled child is not revived. A denied, continued
without changes, stale, expired, or no-longer-eligible parent returns no child
packet. If none is available, report the recommendation and continue read-only
or stop.

## 4. Create or replace notes

Create only an exact authorized path:

```sh
scholium note create <vault>:<relative-path> --from <markdown-file>
```

Replace an existing note only from a complete UTF-8 Markdown file and the fingerprint returned by the latest read:

```sh
scholium note replace <vault>:<relative-path> --from <markdown-file> --expected <sha256>
```

After replacement, reread the note. On `Revision mismatch`, stop, discard the pending write assumption, and rebuild the edit from the current version. Never retry by substituting a new fingerprint without reconsidering the changed content.

Use `move`, `set-aside`, `trash`, or permanent `delete` only when the researcher explicitly requests that exact lifecycle action. They are not integration shortcuts.

## 5. Read and answer Discuss

When a Discussion ID is supplied, retrieve its exact record:

```sh
scholium discuss show <discussion-id> --triptych <triptych> --format json
```

Treat the initial instruction, Prepared Instructions, included Comments, follow-up Comments, and agent Responses as the scholarly exchange. Prepared Instructions are transport history, not a methodological authority or a required research record. A selected note fingerprint stored in the Discussion is advisory request-time context; reread the live note before every mutation.

For Discuss, the JSON record contains the exact Discussion identity and request snapshot. Use it through `scholium-discussion-protocol`; do not replace it with newer defaults. Missing required identity is invalid current state and must fail closed. Copied instructions must identify the Discussion ID and Triptych selector so the agent can retrieve the exact record without guessing.

Use `discuss list` only when discovery is necessary. Filter by Triptych and note whenever possible.

Persist the final agent Response:

```sh
scholium discuss reply <discussion-id> --triptych <triptych> --agent <agent-name> --from <response-file>
```

When the response addresses one selected note or Comment, add the exact `--note <vault>:<relative-path>` and, when supplied by Discuss, `--comment <uuid>` selectors.

Use `--from` for multiline responses. Never interpolate untrusted Markdown or researcher text into a shell command. Compose the attributed turn under `scholium-discuss` and persist it under `scholium-discussion-protocol`; include material uncertainty and any needed researcher decision, not commands, token counts, or routine file operations.

## 6. Recommended Bibliography

Recommended Bibliography is a separate Analysis-only lifecycle. Prefer its
typed `nextActions`; recover a prepared request with `bibliography show`. These
commands transport structured reading leads only and never authorize note or
Zotero mutation.

## 7. Failure behavior

Stop the affected operation when:

- the requested Triptych or vault cannot be resolved;
- a selected note no longer belongs to the Discussion or Triptych;
- a note cannot be decoded as UTF-8;
- the expected fingerprint is stale;
- the Discussion store reports a health error;
- the CLI is unavailable or lacks the required command;
- the exact target or authorization is ambiguous.

Also stop when a required `nextActions` command is absent from the installed
CLI. Run `scholium version`, `doctor`, and command-specific help; do not fall
back to guessed options or direct `.scholium` edits.

Report the failure in the active conversation. If a Discussion ID remains writable, also record a concise stopped-state Response there.
