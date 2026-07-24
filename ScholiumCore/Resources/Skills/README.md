# Scholium product Skills

This tree is the release-managed source for Scholium's protected mechanism, bundled Method references, and optional Researcher Skill templates. A Skill is a bounded UTF-8 package with a required `SKILL.md` entry point and optional one-level `references/`, `templates/`, or `evals/` resources.

## Ownership layers

### System Skills

System Skills are protected mechanism only:

- `scholium-core-protocol` owns identity, revision, authority, privacy, completion, and Research Record boundaries;
- `scholium-research-integration` adapts prepared Actions to protected reads and writes;
- `scholium-discussion-protocol` owns Discussion identity and persistence, not philosophical dialogue method;
- `scholium-zotero-integration` owns bounded library access.

They cannot be edited or replaced by a research method.

### Bundled Method references

Seven ordinary methods each support one researcher-visible Action:

| Action | Method package | Target |
| --- | --- | --- |
| Discuss | `scholium-discuss` | Analysis, Topic, or Work; no Markdown write |
| Analyze | `scholium-analyze` | current Analysis |
| Synthesize | `scholium-synthesize` | current Topic |
| Write | `scholium-write` | current Work |
| Critique | `scholium-critique` | current Work; read-only |
| Check Fidelity | `scholium-content-fidelity` | Analysis, Topic, or Work; read-only |
| Manuscript | `scholium-manuscript` | current Work; optional and hidden by default |

Analyze adapts between initial analysis and reanalysis without exposing a mode selector. Critical pressure is part of its method after source-grounded reconstruction. Synthesize is a separate Topic method. The retained `develop` and `revise` Function identifiers are internal execution compatibility only.

These packages are usable defaults, not best methods or certification. A new Triptych copies the first six into independent, directly editable working packages and binds them through Action-keyed binding v2. The bundled packages remain read-only references for initial installation, comparison, and explicit restoration; they are never runtime fallback.

Manuscript ships only as an optional reference. Its new-Triptych v2 state is explicitly disabled, and a run remains unavailable until the researcher activates a compatible Triptych-local Method. The retained Function machinery and legacy Function binding are not implicit enable routes.

Protected System packages are seeded by the Action resolver rather than trusted to an editable Method's dependency list. A local Method may be self-contained or name bounded System/specialist dependencies, but no Triptych-local dependency edge may execute another Method: each Action packet contains exactly its one bound complete Method. Assembly snapshots all package bytes coherently, while selected Practices, citation styles, and Fidelity checks retain their narrower resource selections. Direct edits and bundled restores preserve displaced complete packages through the machine-local Research Guidance snapshot inventory; cross-volume fallback also retains and reports the hidden portable package instead of deleting possible late writes.

### Researcher Skill templates

`scholium-philosophical-practices`, `scholium-source-analyzer`, `scholium-prose-control`, and `scholium-citation-verification` remain optional copy-on-adoption templates. They never activate merely because they are present, cannot grant authority, and do not supersede the active ordinary Method.

## Catalog and evaluation

`catalog.yaml` schema 4 records protected ownership, exact Action compatibility, retained internal Function compatibility, modes, dependencies, and bounded resources. Assembly selects the explicit v2 Working Method by Action and fails closed for absent, disabled, invalid, or incompatible state; Function-keyed primary, supplemental, and Practice fields are ignored.

`evals/cases.yaml` is an unexecuted forward prompt/evaluation specification. It enumerates complete source and argument routes, source-unavailable refusal, phase isolation, record boundaries, and adversarial authority cases. Repository tests establish only that its declared Actions, packages, routes, and resources are structurally valid. No runner, agent output, or behavioral oracle is attached yet, so these cases establish neither behavior, philosophical quality, nor Method fidelity.
