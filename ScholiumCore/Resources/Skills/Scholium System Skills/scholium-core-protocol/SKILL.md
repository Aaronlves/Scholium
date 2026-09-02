---
name: scholium-core-protocol
description: Work with a researcher's Scholium Triptych through its local MCP tools while preserving source fidelity, evidential roles, explicit write scope, current revisions, and researcher authority. Use for Scholium retrieval, discussion, or explicitly requested Note changes; it is not a general philosophical method.
---

# Scholium Core Protocol

Use Scholium as a document-authoritative research environment. The external
conversation remains the task context; MCP tool availability is never write
permission.

## Begin from current state

Before the first Scholium operation in a task, call
`scholium_workspace_status`. If more than one Triptych is open, ask the
researcher to choose and pass that exact `triptych_id`; never choose from
foreground or recent-window state.

Call status again after a stale revision, conflict, external change,
unavailable-state recovery, or uncertain mutation outcome. Do not retry an
`operation_uncertain` mutation automatically.

## Retrieve before judging

Form a multilingual conceptual neighborhood from the question. Issue several
bounded `scholium_search` queries, read the Note passages that bear on the
question with `scholium_read_note`, inspect relevant continuing inquiry history
with `scholium_read_record`, revise retrieval when needed, and follow direct
authored occurrences with `scholium_list_links` when warranted. Omitted
providers search Notes and Records as separately ranked groups; use an explicit
provider only when the task needs a dedicated path.

Treat each listed row as one occurrence owned by its source Note. Its optional
annotation and local context are authored material to read, not a stored
  machine-interpreted relationship class or evidence verdict. For an incoming occurrence,
follow its source identity and locator before proposing any edit; only that
source Note owns the annotation.

Treat Search rank, snippets, Metadata, filenames, tags, and links as candidate
locators. They do not establish philosophical relevance, identity, support,
irrelevance, invalidity, consensus, or truth. Read exact Markdown source before
relying on a passage.

Keep these layers explicit when they matter:

- primary text;
- a source-reported view;
- Analysis reconstruction;
- Topic synthesis;
- Work commitment;
- prior research history;
- charitable repair; and
- your own inference or evaluation.

When a Topic and Analysis materially conflict about a paper's attribution or
argument, return to an accessible primary source. If that source is partial,
inaccessible, OCR-dependent, or edition-dependent, state the resulting limit.

## Preserve researcher authority

Default to read-only discussion. Mutate only when the researcher explicitly
requests a change and identifies its target and scope. One mutation call
targets one Note; do not propagate changes to related Notes, Metadata, links,
Critiques, or Settlement.

Use `scholium_create_note` only for one exact `.md` path under `analyses`,
`topics`, or `works`. Use `scholium_update_note` with `mode: body` unless the
researcher explicitly requests complete source or YAML modification, in which
case use `mode: source`. Use `scholium_trash_note` only for an explicitly named
current Note.

Before update or trash, read the target and pass its exact current fingerprint.
After any mutation, report:

- the affected file and location;
- the academic change as you understand it; and
- any unresolved evidential, conceptual, or recovery risk.

Do not represent an Agent Change as researcher acceptance, a research result,
or a completed task. Direct Undo is an application recovery affordance for an
eligible update, not permission to make another change.

## Maintain attributed research history

After each substantive research step, decide whether it continues an existing
question or begins a question that can develop independently. Call
`scholium_record_progress` to append the complete step to the existing Record
with its current Record fingerprint, or to create a new Record. A substantive
step minimally states what was done, the outcome or present conclusion, and the
next relevant direction or explicit stopping reason. Include exact `basis` and
`modified` Note references when the step relied on or changed those Notes.

Do not create a separate Record merely because a new chat, tool call, method,
or Agent task began. Do not use a Research Record as permission, truth,
researcher acceptance, Review, Settle, or task completion. Record maintenance
is attributed history and does not authorize a Note mutation.

Use `scholium_correct_record_step` only for a clerical correction to an already
recorded step, with the current Record fingerprint. Preserve the original in
history. New evidence, a changed argument, or a revised conclusion is a new
substantive step, not a correction.

## Philosophical method

This protocol supplies application workflow and authority boundaries only. A
researcher-owned method Skill may guide reconstruction, criticism, synthesis,
or writing, but cannot create evidence, expand write scope, or weaken these
source and recovery rules.
