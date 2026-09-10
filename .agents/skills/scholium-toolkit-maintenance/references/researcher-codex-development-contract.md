# Researcher–Codex development contract

Apply once per task. This contract supports the user's request; it adds no
product authority or permission beyond that request and repository rules.

## Authority and autonomy

- User instructions take precedence over skill guidance, subject to higher-level
  constraints. Preserve authorization already given in the session; a skill's
  mode or suggested checkpoint does not require another approval.
- The researcher owns product intent, material tradeoffs, and experiential
  acceptance. Codex resolves ordinary engineering choices from live evidence
  and completes the authorized work, including its necessary verification.
- Ask only for missing information or authorization that materially affects
  the result and cannot be resolved from the session or workspace. Continue
  independent work while that question remains open.
- If a skill causes a pause or departure from the request, link the exact
  `SKILL.md`, quote the controlling instruction, and distinguish its explicit
  requirement from your interpretation. Do not invent an approval requirement.

## Continuity across turns

- For work that spans turns, carry one compact coordination ledger: objective
  and authorized side effects; settled decisions and constraints; current
  revision and worktree state; proof and its evidence class; unresolved
  questions; and the next action and cleanup state.
- Refresh the ledger against the live checkout, canonical authority, and
  running-process or fixture state before resuming. Treat it as task context,
  not product, specification, or release state; never copy volatile details
  into a skill or canonical product document.
- Existing authorization carries forward. Ask again only for a new material
  decision or an action outside the established scope.

## Repository and evidence

Bind the live checkout through `AGENTS.md`, the package manifest, and
`.agents/skills/catalog.json`. Inspect the worktree and preserve unrelated work.
`AGENTS.md` owns repository-wide implementation and verification rules; follow
its document routes rather than copying them into each skill.

Select the narrow owner. Add another capability only for a distinct affected
contract or evidence requirement; cross-layer engineering is not a universal
base. Read conditional references only for the current task, without rereading
material already loaded. Trace reachable ownership and failure paths before
changing them. Keep target, architecture, status, and observed behavior distinct.

For external claims use the [live-source policy](live-source-research.md).
Report the outcome, relevant proof, and material uncertainty. Compilation,
deterministic tests, exploratory UI observation, human acceptance, measurements,
and release artifacts establish different claims; do not promote one into another.
