# Scholium Swift index boundary checklist

The exact search schema, tokenizer-policy version, privacy policy, storage
location, and cutover belong in current product and implementation authority.
Use this checklist to design an engine boundary; do not substitute it for an
adopted contract.

## Authorized build input

- Apply current role, access, inclusion, and privacy rules before indexing.
- Supply one immutable owned snapshot with stable vault identity, normalized
  relative path, exact source fingerprint, and active contract identities.
- Never give an index adapter a security bookmark, arbitrary path access,
  mutation authorization, or an `allowed` flag that delegates eligibility.
- Keep raw exact values and derived search terms distinct. The engine may return
  retrieval leads, never authoritative Markdown or philosophical evidence.

## Token and position identity

- Version normalization, tokenizer, dictionary or model, term expansion,
  position, phrase, and raw-field policy as one coherent token-policy identity.
- Apply the same policy to document and query text without exposing raw backend
  grammar to the caller.
- Store enough checked source identity to reject stale snippets and highlights.
- Define conversions among UTF-8 bytes, Swift string indices, UTF-16 offsets,
  and one-based full-file lines; fail rather than clamp an invalid boundary.
- Preserve exact identifiers and researcher terminology in raw fields even when
  natural-language fields use normalization or alternatives.

## Generated state and ownership

- Store only disposable derived state outside every research vault.
- Keep one writer owner. Build or rebuild in staging and expose a generation
  only after its rows, manifest, contract versions, and integrity checks commit.
- Record the engine, schema, token policy, source snapshot, privacy policy,
  corpus fingerprint, and per-document fingerprints required for deterministic
  incompatibility detection.
- Reject stale completion when a newer snapshot exists. Cancellation must not
  publish partial state.
- Treat add, edit, rename, and delete as explicit mutations whose final state is
  equivalent to a clean rebuild.

## Query and federation

- Accept structured queries and typed errors; bind every result to the request,
  vault, source revision, generation, and active policy.
- Apply authorization before selecting indexes and preserve vault identity
  through ranking and merging.
- Define one federation policy; do not merge raw backend scores from independent
  corpora as directly comparable values.
- Return the complete owned result contract required by both GUI and CLI.
- Derive visible source context from current exact documents unless a separately
  adopted revision-bound representation proves equivalent.

## Failure, privacy, and recovery

- Reject schema, token-policy, privacy, source, or generation mismatch and use
  only the declared recovery or rebuild path.
- Quarantine or delete corrupt derived state without touching research files.
- Keep the last verified generation only when the current contract explicitly
  permits stale service and identifies it visibly.
- Bound dependency initialization, cancellation, memory, and shutdown. A native
  tokenizer failure must not crash the app or widen filesystem authority.
- Never log or persist queries, indexed text, tokens, snippets, note titles, or
  research paths in diagnostics or benchmark artifacts.

## Equivalence oracle

For one frozen authorized snapshot and contract version, compare a clean rebuild
with every supported mutation history and with the active engine when shadowing.
Verify result identity and order, filters, fields, phrases, positions, snippets,
Unicode validity, source revisions, generation manifests, privacy exclusions,
failure recovery, and GUI/CLI parity. Record every intentional semantic change
in the owning authorities before cutover.
