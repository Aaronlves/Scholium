# Philosophical Knowledge-Base Workflows

## Contents

- [Treat durability as a scholarly transition](#treat-durability-as-a-scholarly-transition)
- [Build a bounded task packet](#build-a-bounded-task-packet)
- [Use Research Units](#use-research-units)
- [Keep properties minimal](#keep-properties-minimal)
- [Separate analysis, integration, and settlement](#separate-analysis-integration-and-settlement)
- [Preserve notes during mutation](#preserve-notes-during-mutation)
- [Use links without fabricating relations](#use-links-without-fabricating-relations)
- [Keep Dialogue scholarly](#keep-dialogue-scholarly)
- [Control status and audit](#control-status-and-audit)
- [Design external integrations](#design-external-integrations)

## Treat durability as a scholarly transition

Do not treat “save the output” as a routine formatting instruction. Moving content into a durable knowledge base changes its epistemic and practical role.

Distinguish:

```text
Source or evidence
        ↓
Analysis, reconstruction, or Dialogue
        ↓
Candidate integration
        ↓
Researcher-authorized or convention-authorized durable update
        ↓
Reviewed or settled research content
```

The arrows are not automatic. A source does not directly write a conclusion; an agent response is not automatically accepted; a polished paragraph is not thereby verified; and a file edit does not itself settle a philosophical question.

Design separate methods for cognition and persistence when their evidence, permission, or audit needs differ. Source analysis and source-to-note integration are usually distinct operations even when one request sequences both.

## Build a bounded task packet

Before a durable operation, assemble only the facts required to act safely:

```text
Intellectual mode and submode:
Research object:
Research question or desired change:
Declared epistemic scope:
Available sources and access status:
Selected note, text, or Dialogue:
Current revision or fingerprint:
Read set:
Write set:
Permission:
Selected methods or Practices:
Output:
Status effect:
Durability expectation:
Conflict and stop condition:
```

The research object and scope control what the result is entitled to claim. The write set controls what the agent may change. Do not confuse either with all technically reachable files.

## Use Research Units

Use a Research Unit when a durable note needs an explicit epistemic scope: what object or domain the note concerns and what its claims apply to.

Keep the concept minimal. In a Scholium-like system it may be stored in YAML and presented as **Research Status**, but the scholarly idea is independent of that representation.

Examples:

- an Analysis declares the source and the actual segment analyzed;
- a Topic declares the conceptual, argumentative, or debate domain synthesized;
- a Work declares the paper, chapter, or project question developed;
- a Dialogue declares the selected notes, text, source, or research issue addressed.

Store only scope that cannot be reliably derived elsewhere. Use links and system state to derive backlinks, counts, coverage visualizations, or relationships. Keep `limitations` only when they materially constrain interpretation.

Distinguish a **session analysis unit** from the **durable Research Unit**. A long book may be analyzed chapter by chapter while one cumulative Analysis file is maintained. After each session, expand the durable Research Unit only to material genuinely represented and reviewed in the cumulative file. Do not create one note per chapter by default, and do not claim whole-book coverage because the current source object is a book.

Require a scope check before every substantive addition:

- Does the new claim concern the declared unit?
- Does it depend on material outside that unit?
- Should the unit expand, remain unchanged, or gain a limitation?
- Would the broader claim overstate actual reading or evidential support?

A missing Research Unit means scope is undeclared, not unlimited.

## Keep properties minimal

Require agents to fill only properties that affect scholarly interpretation, validation, retrieval, display, or workflow state and that cannot safely be app-owned or derived.

Do not require agents to maintain:

- creation time;
- modification time;
- word count;
- backlinks or link counts;
- file size;
- other system history or calculated values.

Treat creation and modification time as app-owned history. Preserve legacy timestamp frontmatter unless an explicitly authorized migration owns it; do not infer or refresh it during ordinary research edits.

For every required property define:

- meaning in the research domain;
- allowed values or shape;
- evidence needed to fill or change it;
- owner: agent, researcher, or application;
- transition criteria;
- whether it is stored or derived;
- failure behavior when the value is unknown.

Do not make a template field mandatory merely because it is available.

## Separate analysis, integration, and settlement

Use explicit bridges:

### Source to analysis

Record what the source says, how it is reconstructed, the actual coverage, locators, and limitations. Keep evaluation distinct.

### Source to note

Integrate verified source material into selected notes with an explicit evidential role: definition, premise support, objection, reply, case, historical background, debate position, or follow-up lead. Do not copy an analysis wholesale merely because it exists.

### Dialogue to note

Incorporate only a researcher-settled conclusion or an explicitly authorized revision. Do not treat every agent response or intermediate comment as accepted knowledge.

### Analysis to project use

Keep **project relevance** separate from **importance in the real debate**. A source may be central to the field but irrelevant to the current project, or highly useful to the project while peripheral in the wider debate. Ratings require reasons, a defined scale, and adequate debate evidence; they must not control reading depth or substitute for analysis.

### Writing to note or Work

Preserve the intended thesis and distinguish advisory prose, a patch proposal, and an authorized direct edit. Writing quality cannot cure false attribution, invalid reasoning, or unsupported premises.

## Preserve notes during mutation

Require the agent to:

1. inspect the current target and applicable local instructions;
2. verify the current revision or fingerprint when the system supports it;
3. declare the exact write subset;
4. preserve unrelated Markdown, frontmatter, links, citations, comments, structure, and custom fields;
5. make the smallest coherent substantive change;
6. detect concurrent or external change and stop rather than choose silently;
7. validate syntax, schema, links, and the philosophical content affected;
8. report the academic change and unresolved risks.

Do not normalize an entire file, reorder frontmatter, rename headings, or “clean up” prose outside the task merely because an editor can. Do not edit machine state directly when the application supplies a supported command or transaction path.

## Use links without fabricating relations

Treat links as possible scholarly relations, not mere navigation. Require a warranted relation before adding one.

Examples include:

- source **analyzed by** Analysis;
- argument **uses** a premise;
- objection **targets** a claim;
- reply **answers** an objection;
- Analysis **contributes to** Topic;
- Topic **informs** Work.

Store the primary relation once when bidirectional indexing can derive the inverse. Do not encode both directions as independent claims. Do not infer a strong relation from keyword overlap, co-occurrence, or an existing backlink alone.

## Keep Dialogue scholarly

Design Dialogue as the concise, inspectable record of scholarly interaction:

```text
Researcher Comment
Agent Response
Follow-up Comment
Follow-up Response
```

Keep hidden prompt templates, system instructions, model parameters, token counts, and sentence-level generation metadata outside the scholarly record unless a separate debugging system needs them.

Allow researcher-selected presentation contracts, such as:

- concise Academic Change or Academic Outcome;
- Critical Reflection;
- Remaining Questions;
- Debate Context or Philosophical Significance;
- Research Directions;
- another explicitly selected scholarly module.

Multi-selection should compose a concise response, not duplicate the note or create a page of generic reflection. Treat response choices as presentation preferences, not permission to edit notes.

If Comments may be condensed, distinguish:

- keep all Comments;
- preserve Academic Intentions;
- preserve one overall research objective.

Never silently change philosophical meaning, remove a material qualification, or present a summary as verbatim. The researcher owns the preservation choice.

## Control status and audit

Define status as a scholarly or workflow state with explicit transition criteria. Do not let an agent mark content `reviewed`, `verified`, `settled`, or equivalent merely because it produced or edited it.

Separate:

- workflow completion;
- source coverage;
- confidence or unresolved uncertainty;
- researcher adoption;
- exact-version audit status.

Bind an audit to the exact target revision and declared scope. A substantive later change makes the earlier audit stale for that new version. Avoid recursive or duplicate audits; normally audit the final substantively changed version once.

## Design external integrations

Keep integrations such as Zotero, web retrieval, or citation tools as bounded specialists or application adapters.

- Bibliographic metadata is not evidence that the source supports a philosophical claim.
- A citation style is a researcher- or venue-selected convention, not a universal philosophical method.
- Retrieval permission is not write permission.
- A local MCP or CLI capability must declare exactly what it can access and change.
- Do not send private research content to an external service without explicit authorization.
- Verify imported records or attachments after a guarded write when writes are supported.
- Report unavailable sources and transport failures rather than fabricating a result.

Let researchers install or author convention-specific citation skills. Do not hard-code one format into universal philosophical methodology.
