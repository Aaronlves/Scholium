# Scholium Active Run

Use this reference for the current authenticated Run's evidence, Discussion
reply, and state-revalidation actions.

Follow each typed `next_actions` requirement. Read the exact current Target and
execute every `required` Fidelity inspection before judging it. Execute
selected-Material, formal-source, Recommended Reading, related-Note, and Search
queries marked `when_needed` whenever the registered Method and research
question can benefit from that evidence. Use repeated bounded queries when a
substantial literature set is warranted; do not stop at a small arbitrary
count merely to minimize reading. Search uses `agent query` or the exact
returned query action and remains bounded to the current Triptych.

A current `source_material` item carries one base64-encoded exact byte page,
the whole-source fingerprint, and no filesystem locator. Decode and preserve
those bytes as source evidence. When `nextMaterialCursor` is present, keep the
same request and clause identities, copy that cursor into `material_cursor`,
and continue until no cursor remains. Do not replace missing pages with
metadata, an Analysis Note, or a similarly named file.

Calling a query is not evidence that returned material was read, relied on, or
supports the Result. Scholium does not request, infer, or persist reading
history or source-use testimony. Treat every response according to its returned
currentness, provenance, scope, and access limits; do not turn delivery into
support, relevance, or researcher acceptance.

For a Discuss Run, read the required `scholium-discussion-protocol` before
composing the attributed response, then use `agent discuss-reply` once with one
stable `statement_id`. An exact retry is idempotent. A successful reply
atomically forms the portable Research Record and completes the Discussion; it
does not edit a Note and requires no separate Finish.

Use `agent reload` whenever the current authenticated Run state is uncertain.
A confirmed Run write advances that member's current revision; reload and the
returned exact-target query must use that self-written revision before Result
finalization. This does not weaken drift detection: any later external change
still returns `stale_run`.
A `stale_run` response means an exact Target, Material, or formal source
boundary changed. Stop that Run; do not retry a query, reply, write, or Result
against the changed boundary.

Do not infer a protocol phase from the order or presence of actions. The
Application may expose required and when-needed actions together; each action's
typed requirement and current response govern its use.
