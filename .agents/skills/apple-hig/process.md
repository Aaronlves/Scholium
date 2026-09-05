# Apple HIG Update Process

Use this procedure to refresh the local corpus against Apple's current Human Interface Guidelines. The official source remains authoritative; the corpus exists to make that source compact, routable, auditable, and usable offline.

## Source Boundary

- HIG root: `https://developer.apple.com/design/human-interface-guidelines/`
- DocC JSON root: `https://developer.apple.com/tutorials/data/design/human-interface-guidelines.json`
- Page JSON: `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/{slug}.json`
- Design Resources and official Apple design sessions are supplementary sources, not substitutes for a topic's HIG page.

Never infer freshness from a version number in skill prose. Record freshness in a dated source snapshot.

## 1. Capture A Complete Snapshot

From any working directory, run:

```bash
python3 /path/to/apple-hig/scripts/crawl_apple_hig.py --resume
python3 /path/to/apple-hig/scripts/render_apple_hig.py sources/apple-hig-YYYY-MM-DD
```

The crawler stores raw JSON, inventory, failures, and initial dispositions under `sources/apple-hig-YYYY-MM-DD/`. Retry transient failures. Classify persistent HTTP errors as removed, renamed, or unreachable only after checking the current official site.

Do not begin distillation until the inventory is complete and every failure is explained.

## 2. Compare With The Prior Audited State

Compare canonical slugs, source hashes, page changelogs, the HIG root's “New and updated” section, and the prior accepted inventory.

- A changed hash is a review signal, not proof of a semantic change.
- An unchanged slug or changelog is not proof of full coverage.
- A missing alias is not a removed topic if its canonical page remains available.
- Every current page needs one disposition, and every local distilled file must map to a current page or an explicit removal decision.

Use dispositions that state the evidence actually obtained. Distinguish full current-source review from changelog triage or carried-forward prior audit; never promote one into the other.

## 3. Review And Distill

Review all topics Apple currently highlights, every page with a meaningful semantic diff, new or renamed pages, and any local file implicated by changed terminology or routing.

When editing `distilled/*.md`:

- preserve exact values, platform distinctions, API and framework names, terminology, and do/do-not rules;
- remove framing, marketing prose, and examples that add no usable rule;
- keep platform-specific guidance under explicit platform headings;
- keep triggers representative rather than exhaustive;
- add only source-backed `related` links;
- treat collection pages as routing evidence unless they contain independent durable guidance.

Record the reviewed source, finding, and resulting file change in the dated snapshot's `verification/` directory.

## 4. Regenerate And Validate

Run:

```bash
python3 /path/to/apple-hig/scripts/generate_routing_index.py
python3 /path/to/apple-hig/scripts/generate_routing_index.py --check
python3 /path/to/apple-hig/scripts/validate_corpus.py
python3 /path/to/scholium-toolkit-maintenance/scripts/validate_toolkit.py
python3 Tools/Scripts/validate-scholium-toolkit-catalog.py
```

The corpus validator checks structure and routing, not source fidelity. A passing validator is necessary but does not replace the dated review evidence.

## 5. Acceptance

Before calling a refresh complete, confirm:

- the crawl has no unexplained failures;
- current, removed, renamed, collection-only, and carried-forward pages have explicit dispositions;
- every changed distillation has source-review evidence;
- the generated routing index is current;
- broad, platform, component, accessibility, and exact-value prompts route only to necessary references;
- offline answers disclose snapshot age and avoid claiming current guidance.

Package the runtime skill only after these checks pass. Keep raw sources, maintenance scripts, and review notes out of the runtime archive.
