# Benchmark protocol routing

The sole canonical benchmark protocol is
[`Docs/PERFORMANCE_BENCHMARK.md`](../../../../Docs/PERFORMANCE_BENCHMARK.md) in
the Scholium checkout. Read that document for RDF-1, the fixture generator,
thresholds, state definitions, release-artifact requirements, correctness
checks, five warm-ups, 30 retained samples, gate status, and reporting.

Use `Tools/Scripts/generate-rdf1.py` from the repository root to create a
disposable synthetic fixture. The generator writes to `/tmp` by default.
Never use a private research vault or a corpus derived from private research
content.

This reference exists only to preserve the skill's relative link. It must not
define a second fixture root, sample count, quantile method, threshold set, or
gate status. Internal performance tests and Debug or incomplete-fixture runs
remain regression or scenario-only evidence.
