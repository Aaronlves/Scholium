# Discuss Response Contract

## 1. Two levels of state

Keep the mutable Triptych default separate from the immutable request-time choice.

| State | Purpose | Authority |
| --- | --- | --- |
| Discuss Defaults | Remembers the researcher’s current response defaults for the Triptych | Default for a new Discuss request only |
| Discuss snapshot | Records the exact choices used when **Copy Instructions for Agent** created one Discussion | Authoritative for that Discussion |

This separation prevents a later panel change from changing how an earlier request should be answered.

## 2. Exact profile location

Given the Works vault selected for a Triptych, Scholium stores the portable profile beside Works:

```text
<Works parent>/.scholium/dialogue-response.json
```

Example:

```text
/Research/Ethics/Works
/Research/Ethics/.scholium/dialogue-response.json
```

Scholium creates and updates this legacy-named compatibility file. Agents may inspect it only when the researcher explicitly asks about current Discuss Defaults. Agents never write it directly, and never use it to replace a Discussion's immutable request snapshot.

## 3. Portable profile shape

Use a small, versioned JSON document:

```json
{
  "schemaVersion": 1,
  "profileRevision": "8E6C1794-8918-4DF3-9B9A-AC0B5B4BA31E",
  "updatedAt": "2026-07-15T10:30:00Z",
  "base": "academic-outcome",
  "modules": [
    "critical-reflection",
    "remaining-questions"
  ],
  "concision": "concise",
  "commentPreservation": "keep-academic-intentions"
}
```

`base` is always `academic-outcome`. An empty `modules` array is valid. Fidelity, uncertainty, failure disclosure, and researcher control are universal rules and are never optional modules.

## 4. Request snapshot

When the researcher copies a Discuss request, Scholium snapshots the effective profile into the request record as `responseContract`. The snapshot contains:

```json
{
  "schemaVersion": 1,
  "profileRevision": "8E6C1794-8918-4DF3-9B9A-AC0B5B4BA31E",
  "base": "academic-outcome",
  "modules": ["critical-reflection", "remaining-questions"],
  "concision": "concise",
  "commentPreservation": "keep-academic-intentions"
}
```

The copied transport instructions must identify the Discussion ID and Triptych selector. The agent retrieves the complete snapshot through:

```sh
scholium discuss show <discussion-id> --triptych <triptych> --format json
```

The raw Application Support compatibility store is not an agent-facing interface. Do not locate or edit it directly.

## 5. Response modules

The initial module vocabulary is intentionally small:

| ID | Scholarly question |
| --- | --- |
| `critical-reflection` | What important assumption, weakness, tension, counterexample, or interpretive risk remains? |
| `remaining-questions` | What directly relevant questions remain unresolved by the completed work? |
| `philosophical-significance` | Why does the result matter philosophically, and what is at stake? |
| `debate-context` | How does the result bear on the relevant debate, positions, motivations, or costs? |
| `research-directions` | What bounded next investigation is warranted by an identified gap or pressure? |

These modules are response perspectives, not Workflow Skills or researcher-owned Philosophical Practices. Selecting one changes what the closing Response foregrounds; it does not activate a new workflow or expand retrieval.

Consider every selected module and allocate methodological effort flexibly according to the actual question, checked materials, and warranted findings. A module may yield no distinct finding. Do not silently skip a selected module, manufacture filler, expose an allocation ledger, or turn response-module selection into a claim about word count or philosophical importance. Academic Outcome and mandatory integrity notices remain required independently of optional modules.

## 6. Comment preservation

`commentPreservation` controls how researcher Comments are presented in the concise scholarly record:

| ID | Meaning |
| --- | --- |
| `keep-all-comments` | Preserve every scholarly Comment in the exchange |
| `keep-academic-intentions` | Preserve each intellectual request, objection, qualification, or decision while omitting conversational noise |
| `keep-overall-comment` | Preserve one faithful synthesis of the overall research objective |

The original app-owned Comments remain unchanged unless the adopted product design later specifies a separate archival rule. A condensed presentation must never masquerade as verbatim text.

## 7. Resolution precedence

Resolve the contract only from the `responseContract` snapshot in the exact
Discussion record. The portable Triptych Discuss Defaults create future request
snapshots; they never answer an existing Discussion. A record without a snapshot
is invalid current state and must fail closed rather than inventing a contract.

## 8. Invalid or future values

- Reject a missing or unsupported `schemaVersion` as an exact-contract failure.
- Apply recognized modules in their stored order.
- Report unknown module IDs without translating them into a familiar module.
- Deduplicate repeated module IDs without duplicating content.
- Treat an absent `modules` array as empty only for a recognized schema version.
- Never let malformed response configuration prevent disclosure of a failed write, source limitation, conflict, or needed researcher decision.

## 9. Current implementation boundary

The current Scholium implementation creates and updates the portable
`dialogue-response.json` compatibility profile, snapshots the effective profile into each
new Discuss record as `responseContract`, and places the Discussion ID and
Triptych selector in the copied transport instructions. Agents retrieve the
exact request snapshot through the supported `scholium discuss show` command;
they do not read or edit the raw Application Support Dialogue store.

Earlier Dialogue entries without a snapshot are archive state. Scholium
does not expose them as current Discuss requests, and an external agent must not
infer or manufacture the missing researcher selection.
