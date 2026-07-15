# Scholium Rust index wire contract

This reference is the sole authority for the Swift–Rust build and query envelopes, generation identity, and wire-level failure behavior. `scholium-derived-index-integrity` owns the active versioned user-visible search contract. A backend or protocol change must not silently redefine search semantics.

## Contents

- [Swift-owned build input](#swift-owned-build-input)
- [Rust-owned derived state](#rust-owned-derived-state)
- [Query boundary](#query-boundary)
- [Failure and privacy behavior](#failure-and-privacy-behavior)
- [Equivalence oracle](#equivalence-oracle)

## Swift-owned build input

Swift applies the live role and privacy policy before crossing the boundary. It omits unauthorized documents and fields rather than sending research text with an “allowed” Boolean that delegates the decision to Rust. Semantic indexing is outside this lexical-engine contract; any future semantic engine needs its own Swift-filtered projection and researcher-approved policy.

Send one complete snapshot in a build envelope equivalent to:

```text
IndexBuildRequest
  protocol_version
  request_id
  source_snapshot_id
  search_contract_version
  privacy_policy_version
  vault_id
  documents[]

IndexDocument
  vault_id
  vault_role
  relative_path
  content_fingerprint
  title
  aliases[]
  tags[]
  authors[]
  filterable_metadata{}
  headings[]
  body
```

Swift constructs this request from one complete `VaultStore` snapshot. Rust receives owned values, not bookmark data, unconstrained filesystem authority, or disallowed field text. The repeated vault identity on each document is defense-in-depth against mixed-vault batches.

After fully validating and publishing the generation, return:

```text
IndexBuildResponse
  protocol_version
  request_id
  vault_id
  source_snapshot_id
  generation_id
  search_contract_version
  privacy_policy_version
  manifest_fingerprint
```

Do not return a successful build response for a staged, partial, cancelled, or unpublished generation. Build failures return a typed, content-free error carrying `protocol_version`, `request_id`, and `source_snapshot_id` when known.

## Rust-owned derived state

Each published generation records:

```text
manifest
  generation_id
  engine_name/version
  protocol_version
  schema_version
  search_contract_version
  tokenizer_name/version/configuration
  privacy_policy_version
  vault_id
  source_snapshot_id
  document_count
  document_identity_and_fingerprint[]
  created_at
```

Create a new generation in a staging directory. Flush and validate it, then atomically publish a small current-generation pointer or rename the generation into place. Never mutate a currently visible generation into a half-new state. Rust may write only this disposable derived tree outside every vault.

## Query boundary

Use structured requests rather than a backend query string:

```text
SearchRequest
  protocol_version
  request_id
  vault_id
  generation_id?
  search_contract_version
  privacy_policy_version
  terms[]
  phrase?
  prefix_allowed
  filters{}
  limit
```

An omitted `generation_id` requests the service's current published generation at dispatch time. The normal UI may use this convenience, but must still compare the returned generation with the vault's current published-generation pointer immediately before delivery. Return one response envelope:

```text
SearchResponse
  protocol_version
  request_id
  vault_id
  generation_id
  source_snapshot_id
  search_contract_version
  privacy_policy_version
  freshness  # current | stale
  hits[]

SearchHit
  vault_id
  relative_path
  content_fingerprint
  score
  matched_field
  matched_terms[]
```

Swift accepts a response only when its protocol, request, vault, requested-generation, search-contract, and privacy-policy identities match and its `request_id` is still the live UI request. Immediately before delivery, Swift compares `generation_id` with the vault's current published-generation pointer. If a newer complete generation has replaced it, discard the response and reissue the query even when its source snapshot and hit fingerprints would otherwise pass. Swift derives freshness by comparing `source_snapshot_id` with the current complete vault snapshot. A last complete generation built under the current privacy policy may be served during an unfinished rebuild only with `freshness = stale` and only while it remains the current published-generation pointer; Swift revalidates every hit fingerprint against the current exact note before displaying a snippet or source line and drops or requeries mismatched hits.

Federated cross-vault search issues vault-scoped requests and validates every response independently before combining them under the explicit grouping or normalization policy. Preserve each vault's generation, source snapshot, freshness, search-contract, and privacy-policy identity in the aggregate. If one response fails generation or policy validation, requery or use the authorized Swift fallback for that vault; do not merge it into the current aggregate. Apply each vault role's Swift-owned privacy policy before its build and query boundary—authorization in one vault never widens another vault's corpus. Never hide independently built generations behind one synthetic corpus identity or compare raw backend scores as though they came from one corpus.

Swift derives visible snippets and source lines from current exact documents. Do not return a raw pointer, Rust lifetime, backend document ID, or offset with an unspecified Unicode unit. A prototype that returns snippets must use owned plain/match fragments, bind them to the response generation and source fingerprint, and preserve the same no-logging boundary.

## Failure and privacy behavior

- Protocol or search-contract mismatch: disable the Rust engine and use the Swift fallback.
- Privacy-policy mismatch: reject the generation and rebuild from a freshly policy-filtered Swift projection; never serve it as stale.
- Stale build completion: reject it when a newer source snapshot exists; never publish it as current.
- Last complete generation during rebuild: it may remain queryable only through the explicit stale response described above and only until a newer complete generation becomes the published pointer.
- Corruption or missing segment: quarantine or delete derived state and rebuild; never repair research files.
- Rust process crash: preserve the app and vault, restart with a bounded policy, then fall back to Swift.
- Cancellation: stop work and leave the current published generation unchanged.
- Query syntax error: return a typed, content-free diagnostic; never log or persist the research query, indexed fields, snippets, or note text.

## Equivalence oracle

For one frozen snapshot and active search-contract version, a clean full rebuild and any incremental mutation history must return contract-conformant normalized results. Compare:

- result identities and stable order;
- filters and field matches;
- snippets and Unicode validity;
- source fingerprints;
- response and manifest generation identity;
- index manifest count and Swift-applied privacy exclusions.

A user-visible ranking or query-semantic change must first be approved and versioned under `scholium-derived-index-integrity` with golden queries. A backend migration implements that active version; it does not create an independent product decision.
