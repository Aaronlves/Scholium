# Research-Integration Method

## 1. Shared boundary

Integrate only into exact notes named by the current task. Preserve the difference among source claims, the researcher's formulations, agent reconstructions, criticism, and settled decisions.

Before writing, determine:

- what content is eligible to enter the note;
- what evidential or dialectical role it has;
- where it belongs and what existing claim it affects;
- whether incorporation changes a concept, argument, source role, or researcher commitment;
- what remains uncertain or excluded.

Use the active philosophical Workflow Skill to formulate content. This System Skill controls integration and persistence, not philosophical adequacy by itself.

## 2. `source-to-note`

Require a source analysis or an equivalently checkable source packet. The packet must identify available source material, access limits, reliable locators where possible, and the status of every reconstruction or evaluation used.

Before deciding whether an insertion is eligible, construct a compact source bridge packet:

```text
Source claim, argument, distinction, or passage:
Target claim, question, or burden:
Stable locator:
Verification state:
Difference between source and target preserved:
Maximum warranted attribution:
What this is not evidence for:
How the target may use it:
How the target must not use it:
```

The bridge packet is a reasoning aid, not extra note metadata. Omit a field only when it is genuinely inapplicable; do not fill a missing locator or verification state from memory.

For each proposed insertion:

1. state the source's exact role, such as background, motivation, textual evidence, support, challenge, contrast, example, or unresolved alternative;
2. verify that the source actually plays that role rather than merely sharing vocabulary;
3. distinguish what the source explicitly says from interpretation and charitable reconstruction;
4. preserve qualifications, scope, modality, and disputed readings;
5. integrate only the amount needed by the target note;
6. use citations or source-anchored links where the available material supports them;
7. leave possible later project use to researcher judgment rather than generating a relevance property or score.

Do not let the needs of the target note reshape the source analysis. If integration exposes an ambiguity in the analysis, stop the insertion and return to source analysis with a bounded question.

## 3. `dialogue-to-note`

Treat Dialogue as the scholarly exchange and the note as the durable research formulation. A researcher Comment, follow-up, or explicit decision may establish what the researcher wants; an agent Response alone does not.

Before integration:

1. identify the exact proposition, distinction, objection, reply, or revision the researcher has adopted;
2. separate it from exploratory questions, abandoned alternatives, conversational noise, and unaccepted agent proposals;
3. preserve any qualification, objection, uncertainty, or change of mind that affects the result;
4. if no conclusion is clearly settled, return a candidate formulation or request a decision instead of choosing;
5. update only the selected note and section authorized by the task.

Honor the configured Dialogue preservation level, but never misrepresent a condensed academic intention as a verbatim Comment.

## 4. `authorized-workflow-edit`

Receive an exact change from the active Workflow Skill together with its basis, target, permission, and unresolved risks. Do not expand or philosophically strengthen it during persistence. If the required edit would change a load-bearing commitment beyond the handoff, return to the Workflow Skill rather than improvising inside the adapter.

## 5. Completion

After a successful write:

- reread the note and retain the resulting fingerprint;
- verify that unrelated Markdown, YAML, links, citations, and researcher text remain intact;
- identify the academic change and its evidential status;
- mark substantive philosophical content `audit-needed` for that exact fingerprint;
- write the concise academic Response to Dialogue when the task originated there.
