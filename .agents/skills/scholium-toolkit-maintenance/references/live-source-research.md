# Live-source research policy

This is the sole shared policy for external research performed through
Scholium's local development skills. Apply it whenever a task relies on an
external fact, standard, API, toolchain or dependency behavior, security
guidance, best practice, recommendation, benchmark method, or platform rule.

## Select evidence for the claim

For version-bound API signatures and behavior, inspect the selected SDK,
installed type definitions, or pinned dependency source and its matching official
documentation. Cite the version and local evidence; it does not establish what
is latest. Reuse evidence already inspected in this task while its applicability
holds. Model memory, search snippets, and copied skill summaries are not primary
evidence.

Use live primary sources for current releases, maintenance, security advisories,
platform guidance, recommendations, or unresolved external claims. Follow any
explicit request or higher-level requirement to browse.

1. State the exact claim or decision that needs external support.
2. Select local version-bound evidence or live research under the criteria above,
   matching the compiler, SDK, deployment target, dependency version, and task.
3. Open and inspect the sources themselves. Do not rely on search snippets or
   another author's summary of a source.
4. Prefer primary and official authorities: standards bodies, vendor
   documentation and release notes, selected-toolchain documentation, source
   repositories, security advisories, and original research or benchmark
   methodology.
5. Check publication or update date, version, status, scope, and applicability.
   “Latest” means the newest authoritative source that actually governs the
   selected environment; a newer preview, opinion, or incompatible-version
   page does not displace an applicable stable authority.
6. Use third-party material only to discover alternatives, pitfalls, or
   operational experience. Verify every adopted claim against a primary source
   or a controlled local reproduction.
7. Cross-check a material claim when its primary authority is incomplete,
   ambiguous, contested, security-sensitive, or contradicted by observed
   behavior.

Record the source title and URL or local path, relevant date or version, the claim it
supports, its applicability limits, and any conflict or uncertainty. Keep
source-backed claims separate from Scholium's inference or design choice.

## Keep local and external authority distinct

Resolve Scholium-specific target behavior, architecture, implementation state,
and verified reachability from the repository hierarchy in `AGENTS.md`, the
current `Docs/`, manifests, live construction, call sites, tests, and scripts.
Network sources can explain external mechanisms; they cannot override local
product authority or prove that a local path is implemented.

Skills store durable research procedure and routing only. Do not copy changing
external facts, version tables, release status, or recommendations into skill
prose. Refresh the applicable primary evidence when the task needs it.

## Fail honestly

If the required evidence is unavailable or insufficient, state the affected
claim and continue independent work. Network failure does not invalidate an
answer established by the selected SDK or pinned source, but it limits claims
about current releases or external guidance. Do not describe older evidence as
latest or settle a contract-critical choice without its required authority.
