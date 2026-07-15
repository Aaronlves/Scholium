# Scholium CLI Contract

Use the `scholium` executable as the supported agent-facing boundary for configured Triptychs. Do not infer vault paths or write directly to registered research files when the CLI operation is available.

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

## 3. Create or replace notes

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

## 4. Read and answer Dialogue

When a Dialogue ID is supplied, retrieve its exact record:

```sh
scholium dialogue show <dialogue-id> --triptych <triptych> --format json
```

Treat the initial instruction, included Comments, follow-up Comments, and agent Responses as the scholarly exchange. A legacy `generatedPrompt` field is transport history, not a methodological authority or a required research record. A selected note fingerprint stored in Dialogue is advisory request-time context; reread the live note before every mutation.

For the target Dialogue-response architecture, the JSON record also contains the request-scoped `responseContract` snapshot. Use that snapshot through `scholium-dialogue-response`; do not replace it with a newer Triptych default. Older records may lack the field and must use the explicit legacy fallback. Copied instructions must identify the Dialogue ID and Triptych selector so the agent can retrieve the exact record without guessing.

Use `dialogue list` only when discovery is necessary. Filter by Triptych and note whenever possible.

Persist the final agent Response:

```sh
scholium dialogue reply <dialogue-id> --triptych <triptych> --agent <agent-name> --from <response-file>
```

When the response addresses one selected note or Comment, add the exact `--note <vault>:<relative-path>` and, when supplied by Dialogue, `--comment <uuid>` selectors.

Use `--from` for multiline responses. Never interpolate untrusted Markdown or researcher text into a shell command. Compose the reply under `scholium-dialogue-response`; it should contain the base academic outcome, only the researcher-selected optional modules, material uncertainty, and any needed researcher decision—not commands, token counts, or routine file operations.

## 5. Failure behavior

Stop the affected operation when:

- the requested Triptych or vault cannot be resolved;
- a selected note no longer belongs to the Dialogue or Triptych;
- a note cannot be decoded as UTF-8;
- the expected fingerprint is stale;
- the Dialogue store reports a health error;
- the CLI is unavailable or lacks the required command;
- the exact target or authorization is ambiguous.

Report the failure in the active conversation. If a Dialogue ID remains writable, also record a concise stopped-state Response there.
