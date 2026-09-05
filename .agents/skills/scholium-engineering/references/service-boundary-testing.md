# Service-boundary testing

Use this only when deterministic cross-layer behavior cannot be exercised
through an existing owning target. Resolve live targets, fixtures, scripts, and
test frameworks from the package manifests and neighboring tests.

## Choose the lowest boundary

- **Contract or value:** pure types, parsing, validation, ordering, identity,
  and serialization without platform resources.
- **Application service:** policy, ports, cancellation, typed failure,
  transaction or generation behavior with injected collaborators.
- **Adapter integration:** filesystem, database, process, bookmark, event, or
  packaged-resource behavior that the platform owns.
- **Application or release:** responder, window, accessibility, sandbox,
  signing, packaged resources, or another artifact-only claim.

Create a new test target only when no current target can own the deterministic
contract without importing a presentation or platform dependency. Do not move
platform behavior into a fake pure layer merely to make it easy to test.

## Preserve trustworthy fixtures

- Use generated or disposable nonprivate state with exclusive ownership and
  deterministic cleanup.
- Assert authoritative bytes or values after success and every injected
  failure; keep unsupported source forms unchanged and nonauthorizing.
- Control time, event delivery, randomness, services, and cancellation without
  sleeps or shared mutable global setup.
- Keep specialist fixture matrices with their owning capability rather than
  copying a subsystem inventory here.

Run the narrow test during iteration and apply the repository verification
cadence from `AGENTS.md`. Report the exact boundary proven and any platform,
packaging, UI, performance, or human evidence still separate.
