---
name: scholium-source-analyzer
description: Analyze philosophical and philosophically relevant sources as arguments, conceptual interventions, interpretations, dialectical moves, cases, formal results, normative reasoning, empirical contributions, or topic maps. Use for papers, books, chapters, primary texts, commentaries, handbooks, surveys, and interdisciplinary sources when an external agent has access to the source. Keep source claims, reconstruction, evaluation, and possible research use distinct. This is a complete agent method, not a Scholium Research Function and not a note-writing permission.
---

# Source Analyzer

Apply `scholium-core-protocol`. This package contains a complete source-analysis method. It can operate on a source supplied through Zotero, a local file, an attachment, pasted text, or another available channel; Scholium does not need to store or control the source.

## Keep the product boundary explicit

Source Analyzer has no Research Strip button and declares no `supported_functions`. An external agent may use it whenever the researcher asks to analyze an accessible source. Producing an analysis does not create, update, or authorize a Scholium note. If the researcher later asks to preserve or develop the result in Scholium, begin a separate, explicitly authorized operation against the exact note and current fingerprint.

## Select the analytical form

Read [references/analysis-forms.md](references/analysis-forms.md) and select exactly one form. Default to `analysis-only` when the researcher supplies no project context, and to `analysis-with-handoff-candidates` when project context exists but no later use has been authorized.

## Establish the source packet

Record:

```text
Source object and verified identity:
Source type and philosophical function:
Available version, language, and translation:
Access: complete | partial | excerpted | OCR-derived | unreliable
Session analysis unit:
Research question or requested purpose:
Requested depth: concise | thorough | provisional
Output: ephemeral analysis | durable report | handoff candidates
Selected Practices and attention allocation:
Locator policy:
Stop condition:
```

Never infer whole-source access from metadata, an abstract, an introduction, a prior report, or the existence of a PDF record.

## Load the complete method

Read [references/method.md](references/method.md) completely.

Load conditional references only when triggered:

- read [references/report-templates.md](references/report-templates.md) when a structured durable report is requested;
- read [references/bibliography-and-handoff.md](references/bibliography-and-handoff.md) when screening cited literature or proposing later research uses;
- read [references/source-clusters.md](references/source-clusters.md) for an edited volume, multi-author collection, chapter sequence, or bounded source cluster.

## Compose selected Philosophical Practices

Compatible Practices are `historical-interpreter`, `conceptual-analyst`, and `argument-reconstructionist`. Load only explicitly selected Practice references plus `COMPOSITION-RULES.md`.

Source Analyzer declares these researcher-editable base attention profiles. They are a methodological composition contract, not a claim that source genres objectively or universally require these proportions:

| Dominant source function | Historical Interpreter | Conceptual Analyst | Argument Reconstructionist |
| --- | ---: | ---: | ---: |
| historical or exegetical | 50 | 30 | 20 |
| concept-forming or taxonomic | 20 | 50 | 30 |
| argument-driven or dialectical | 20 | 30 | 50 |
| genuinely hybrid or indeterminate | 34 | 33 | 33 |

Retain only selected Practices and normalize their base weights to total exactly 100%. If the researcher supplies an explicit allocation totaling 100%, use it instead. The percentages allocate methodological attention, not output length. Apply every selected lens for its full share even if it yields no separate paragraph, and never manufacture a finding to fill a share.

## Execute three distinct passes

1. **Orientation** — traverse the complete session unit in source order. Map the question, purpose, provisional thesis or contribution, structure, genre, method, authorial debate framing, turning points, and candidate load-bearing passages. Keep the map provisional.
2. **Analysis** — traverse the complete session unit again. Reconstruct concepts, distinctions, arguments or interpretive moves, objections, replies, concessions, scope, support, and unresolved alternatives. Preserve evidential layers and attach reliable locators.
3. **Review** — traverse the complete session unit a third time while checking the draft against the source. Search for omissions, counterevidence, qualifications, terminology drift, mistaken dialectical roles, weak reconstruction, and quotation or locator error. Revise and mark unresolved uncertainty.

Search results, metadata inspection, text extraction, memory, a prior analysis, and rereading only the draft do not count as source passes. When access is partial or unreliable, perform all three passes over the available unit and issue only a provisional analysis. If a required pass cannot be completed, identify the failed pass and do not claim completed analysis.

## Return

Lead with access status and exact analytical scope, then state the source's function, central question or purpose, principal contribution or organizing purpose, reconstructed structure, and strongest warranted unresolved problem, if any. Separate:

1. source-explicit claims and passages;
2. source-supported reconstruction;
3. analyst-supplied charitable repair;
4. analyst evaluation or objection;
5. possible research use or follow-up lead.

Use locators proportionate to the claim. Mark uncertain metadata, access gaps, translation risks, and unverified debate context. An analysis may later become Material for a Scholium note, but it is not itself a note mutation or settled researcher commitment.
