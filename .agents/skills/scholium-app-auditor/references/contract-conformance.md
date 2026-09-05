# Scholium contract conformance

Use this mode to determine whether target authority, current implementation, tests, status records, and developer guidance describe the same bounded behavior. Remain read-only.

## Build the trace

For each requested feature or cross-cutting contract, separate:

1. **Target product, interface, and release behavior:** Scholium Specification.
2. **Current architecture:** Implementation Architecture.
3. **Dated status claim:** Implementation Status.
4. **Reachable implementation:** package graph, construction, call sites, and resources.
5. **Executable evidence:** focused tests, UI journeys, fixtures, and current artifacts.
6. **Developer guidance:** applicable development skills and repository instructions.

Do not allow a lower layer to redefine a higher authority. Do not describe target behavior as reachable solely because it is canonical.

## Classify divergences

- **Authority contradiction:** two rules within the target specification assign incompatible behavior or meaning.
- **Implementation migration debt:** current reachable behavior differs from one unambiguous target contract.
- **Status defect:** the dated ledger overstates, understates, or misclassifies current evidence.
- **Coverage gap:** consequential reachable or target behavior lacks a credible assertion.
- **Guidance drift:** developer instructions retain removed architecture, workflow, labels, paths, counts, or ownership.
- **Superseded-path residue:** a deprecated decoder, adapter, alias, fallback,
  route, or preservation-only test remains after its contract was replaced.
- **Deferred boundary:** authority explicitly places the capability outside the active release.

Do not count the same divergence in several classes. Identify the highest owning layer and the smallest corrective location.

## Report

Use a compact traceability table with contract, target, current reachability, evidence, classification, consequence, and smallest correction. Lead with confirmed contradictions and material overclaims. Keep design proposals, cutover work, missing proof, and defects separate.

State which authority and implementation surfaces were not checked. “No confirmed divergence” applies only to the inspected trace.
