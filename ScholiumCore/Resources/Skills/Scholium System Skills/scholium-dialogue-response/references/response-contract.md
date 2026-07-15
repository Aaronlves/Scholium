# Dialogue Response Contract

## 1. Two levels of state

Keep the mutable Triptych default separate from the immutable request-time choice.

| State | Purpose | Authority |
| --- | --- | --- |
| Portable profile | Remembers the researcher’s current Scholia-panel defaults for the Triptych | Default for a new Dialogue only |
| Dialogue snapshot | Records the exact choices used when **Copy Instructions for Agent** created one Dialogue | Authoritative for that Dialogue |

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

Scholium creates and updates this file. Agents may inspect it only as a documented legacy fallback or when the researcher explicitly asks about current defaults. Agents never write it directly.

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

When the researcher copies a Dialogue request, Scholium snapshots the effective profile into that `DialogueEntry` as `responseContract`. The snapshot contains:

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

The copied transport instructions must identify the Dialogue ID and Triptych selector. The agent retrieves the complete snapshot through:

```sh
scholium dialogue show <dialogue-id> --triptych <triptych> --format json
```

The raw Application Support Dialogue store is not an agent-facing interface. Do not locate or edit `dialogue.json` directly.

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

## 6. Comment preservation

`commentPreservation` controls how researcher Comments are presented in the concise scholarly record:

| ID | Meaning |
| --- | --- |
| `keep-all-comments` | Preserve every scholarly Comment in the exchange |
| `keep-academic-intentions` | Preserve each intellectual request, objection, qualification, or decision while omitting conversational noise |
| `keep-overall-comment` | Preserve one faithful synthesis of the overall research objective |

The original app-owned Comments remain unchanged unless the adopted product design later specifies a separate archival rule. A condensed presentation must never masquerade as verbatim text.

## 7. Resolution precedence

Resolve the contract in this order:

1. the `responseContract` snapshot in the exact Dialogue record;
2. the portable Triptych profile only when the record predates snapshots;
3. the legacy default: one concise Academic Outcome plus any material unresolved question or required researcher review.

When using level 2 or 3, report `Contract source: legacy-profile` or `legacy-default`. Do not claim to know the exact request-time selection.

## 8. Invalid or future values

- Reject a missing or unsupported `schemaVersion` as an exact-contract failure.
- Apply recognized modules in their stored order.
- Report unknown module IDs without translating them into a familiar module.
- Deduplicate repeated module IDs without duplicating content.
- Treat an absent `modules` array as empty only for a recognized schema version.
- Never let malformed response configuration prevent disclosure of a failed write, source limitation, conflict, or needed researcher decision.

## 9. Current implementation boundary

The current Scholium implementation creates and updates the portable
`dialogue-response.json` profile, snapshots the effective profile into each
new `DialogueEntry` as `responseContract`, and places the Dialogue ID and
Triptych selector in the copied transport instructions. Agents retrieve the
exact request snapshot through the supported `scholium dialogue show` command;
they do not read or edit the raw Application Support Dialogue store.

Legacy Dialogue entries without a snapshot remain readable and are reported as
`legacy-default (request-time selection unavailable)`. The external agent still
must not claim that a researcher-selected contract was retrieved for those
entries.
