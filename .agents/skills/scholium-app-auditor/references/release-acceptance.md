# Scholium release acceptance

Use this mode when the researcher asks whether a release is ready, which gates remain open, or what evidence supports a release decision. Remain read-only unless packaging or external release actions are separately requested through repository engineering.

## Establish the candidate

Identify the release identifier, exact source revision and dirty state, intended build configuration, toolchain, app and CLI artifacts, signing identity, architectures, fixture versions, machine/account class, and distribution scope. If no exact candidate exists, assess readiness of the current tree but do not issue an artifact-level pass.

Read `Docs/SCHOLIUM_SPEC.md` first and follow its declared release chapter for gates and risks, then read the dated `Docs/IMPLEMENTATION_STATUS.md` evidence. Verify current claims against live scripts, tests, artifacts, and retained reports where proportionate. A successful repository verifier is code-health evidence, not automatic UI, accessibility, performance, clean-account, signing, notarization, or recovery acceptance.

## Keep evidence classes separate

- **Implemented:** reachable behavior exists in the candidate source.
- **Repository verified:** unit, integration, architecture, editor, CLI, or deterministic checks passed for an identified tree.
- **QA automated:** named disposable-fixture interaction journeys passed in an identified QA artifact.
- **Release-artifact verified:** the exact candidate was exercised for the named gate.
- **Human accepted:** retained evidence records genuine human input or judgment under the named environment.
- **Waived:** the release owner explicitly accepted a documented residual risk.
- **Open or blocked:** evidence is absent, failing, stale, or cannot be obtained.
- **Deferred:** product authority excludes the capability from this release.

Do not infer one class from another.

## Gate decision

For every applicable gate, record:

- controlling requirement and risk;
- exact evidence and date;
- candidate/artifact identity;
- result and evidence class;
- unresolved failure or limitation;
- required next action and owner; and
- pass, fail, waived, open, blocked, or not applicable.

A gate passes only under its own acceptance rule. A release is ready only when every required gate passes or has an explicit documented waiver. Do not average or numerically score unlike gates.

## Report

Lead with **Ready**, **Not ready**, or **No exact candidate to assess**, followed by the decisive reasons. Then give compact sections for passed gates, open or failed gates, explicit waivers, deferred capabilities, and the shortest evidence-producing next steps.

Do not turn proposed functionality into a release requirement, describe a missing deferred feature as a blocker, or let a broad “tests passed” statement conceal an untested human or release-artifact boundary.
