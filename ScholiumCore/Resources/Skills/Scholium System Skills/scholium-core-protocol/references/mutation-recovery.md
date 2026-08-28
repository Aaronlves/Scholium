# Scholium Mutation and Recovery

Use this reference only when the current Run exposes a mutation route, the
Method needs an additional authorized target, or a submitted mutation requires
conflict or unknown-outcome recovery.

Every write remains bound to one exact document or portable binding identity,
allowed operation, expected revision or proven absence, one-use capability,
and operation identity supplied by Scholium. One member's outcome neither
widens a sibling nor creates a batch rollback.

Use `agent extend-write-set` only when the Method requires another target. The
Application and researcher decide whether that exact member becomes writable;
the request itself grants nothing. For one returned current member, use
`agent write` only for `create_note`, `modify_markdown`, `modify_source`, or
`modify_metadata`.

Portable Analysis-to-Zotero binding is separate from Markdown, Properties, and
the Zotero library. Use `agent write-zotero-binding` for
`set_zotero_binding` or `clear_zotero_binding`; never place a binding operation
in a document-write payload. Set only an exact user/group library identity and
item key already established in the current authorized task. Never infer either
from YAML, title, filename, similarity, or an ambiguous search. These operations
change only Scholium's portable relationship and never change Zotero data. Use
`clear_zotero_binding` only when the task requires removing that relationship.

On a conflict, use the exact returned `agent resolve-write-conflict` action.
Reread the changed source or Metadata owner before deciding whether to create a
new write input. On timeout or unknown outcome, preserve the operation identity
and use the returned recovery action or `agent reload`; do not issue a generic
retry, fallback destination, replacement identity, or retry rename.

Confirmed changes remain committed. Unknown writes, conflicts, and other
recovery duties must become determined before finalization or safe End. Do not
cancel or discard a Run merely to clear those obligations.
