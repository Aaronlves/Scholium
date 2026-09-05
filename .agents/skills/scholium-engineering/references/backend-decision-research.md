# Backend decision research

Use this only when a material backend choice remains after inspecting the live
owner, standard library, platform SDK, current dependencies, their documentation
and type definitions. Typical triggers are a new dependency, storage engine,
protocol, runtime boundary, native component, or custom mechanism. Ordinary
implementation under an established owner uses the backend integration loop.

Apply the toolkit's
[live-source research policy](../../scholium-toolkit-maintenance/references/live-source-research.md)
for external or time-sensitive claims.

## Decide the remaining gap

1. Name the researcher-visible need, current owner, measurable success, and the
   exact gap left by existing project and platform capabilities.
2. Inspect only candidates capable of changing the decision. Verify primary
   documentation, current source and releases, maintenance, license, dependency
   graph, privacy, security, packaging, portability, failure isolation, and
   operational cost as applicable.
3. Compare candidates through the same contract and fixture. Feature count,
   popularity, a clean compile, or an isolated benchmark is not adoption proof.
4. Return one verdict: reuse current capability, extend the current owner,
   adopt a maintained dependency, implement the minimal custom gap, or defer.

## Define an adopted boundary

When the verdict changes implementation, record only the applicable fields:

- responsibility and explicit non-responsibilities;
- authoritative inputs, outputs, prohibited effects, and owner;
- lifetime, isolation, cancellation, ordering, and idempotency;
- transaction or generation boundary, failure, rollback, and recovery;
- containment, privacy, logging, and generated-state placement;
- resource and performance expectations with units when claimed; and
- test oracle, failure injection, packaging evidence, and cutover requirement.

Keep evidence stages distinct: researched decision, disposable fixture proof,
live integration, adversarial recovery proof, and release acceptance. Report
the verdict, decisive evidence, rejected complexity, applicability limits, and
remaining uncertainty.
