# Agent transport

Read this reference only for an unprepared direct-agent task that must discover or retrieve a Skill package, for cold CLI establishment, or when a prepared request lacks the typed action required for recovery. Prepared Actions already carry their exact task state, package revisions, permissions, and typed continuation actions; do not load this generic transport contract merely because the CLI is available.

## Confirm the local boundary

At the start of a cold CLI session, confirm the executable and configuration:

```sh
scholium version --format json
scholium doctor --format json
```

Use hierarchical `scholium help` or command-specific `--help` instead of remembered Beta syntax. If the installed CLI lacks a required command or typed action, report that limitation rather than guessing options or editing `.scholium` state directly.

## Discover exactly one method

Outside a prepared Action, classify the intellectual operation and retrieve exactly one complete matching Method only when discussion, analysis, synthesis, writing, critique, or fidelity checking requires it:

```sh
scholium skills catalog --triptych <triptych> --format text
scholium skills show <method-skill-id> --triptych <triptych> --format text
```

Use `text` for language-agent routing and instruction prose. Catalog text keeps the discriminative routing fields; a selected package shown as text keeps its origin, version, exact revision, modes, compatibility, and complete entry instructions without a redundant JSON envelope. Use JSON only when a programmatic step needs structured fields absent from text, such as the complete `practice_resources` map. Prepared Action state and typed `nextActions` remain JSON.

Do not scan global Codex, plugin, developer-skill, or arbitrary filesystem locations. If the catalog or selected package cannot be retrieved, state the limitation and do not claim to have applied its method.

## Retrieve declared resources

When a selected package instructs you to read one of its references or templates, retrieve that declared resource through Scholium rather than guessing an app-bundle or repository path:

```sh
scholium skills resources <skill-id> --triptych <triptych> --format text
scholium skills show <skill-id> --triptych <triptych> --resource <relative-path> --format text
```

The Triptych selector is optional for a protected bundled package and required for a Triptych-local package. Use the returned package revision when a researcher-owned Practice or specialist method must be recorded. A Markdown link is not evidence that the resource was retrieved.

Current Actions attach one complete Method and every Method resource required by that Action. If recovered state still asks for a secondary method or mode selection, treat it as legacy state and prepare a fresh Action; do not use generic Skill retrieval to mutate the recorded run package.

## Execute typed actions safely

For prepared runs, prefer the typed `nextActions` argument vectors returned by Scholium. Execute the arguments without shell interpolation and replace every required marker in an input template with checked evidence before submission. Use `action show` for process-loss recovery. Never treat successful transport, persistence, or status output as evidence that the philosophical method was adequate.
