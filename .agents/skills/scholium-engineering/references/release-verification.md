# Scholium release verification

Use this checklist for distribution work. Read the current release identity,
artifact set, scripts, output ownership, entitlements, gates, cutover state, and
unsupported-data policy from the specification, implementation status, package
configuration, and live release scripts. Do not preserve them in this
reference.

## Build and package

1. Record the clean worktree or exact uncommitted state being released.
2. Run the repository's current verification and packaging entry points with
   the intended toolchain and signing identity.
3. Confirm every artifact and embedded resource required by the current
   package contract.
4. Resolve the output location and artifact set from the live scripts. Never
   direct release output into the source checkout.
5. Inspect architectures with `lipo -info` or `file`. Do not claim universal support unless every executable and embedded native dependency contains both required slices.

## Signing and channel-specific verification

- Resolve the active release channel, signing identity, entitlements, and
  notarization requirement from the current specification, status, package
  configuration, and live release scripts before choosing a procedure.
- Do not treat ad-hoc signing, Developer ID signing, Apple distribution
  signing, notarization, or stapling as interchangeable evidence. A channel
  that does not require one of them must record it as not applicable rather
  than inventing a gate.
- Preserve the runtime-hardening, sandbox, and entitlement requirements
  declared by the active channel and package contract; do not weaken them just
  to make a local artifact launch.
- Inspect the final signature, designated requirement, and entitlements with
  `codesign -d --verbose=4` and `codesign -d --entitlements :-` whenever the
  active channel signs the artifact.
- Run strict verification after all bundle mutations. Removing only approved
  nonsigned metadata still requires the channel's final verification. Do not
  modify or re-sign a tested artifact; if signed contents change, rebuild and
  repeat the applicable signing and verification procedure.
- Confirm every current entitlement and persisted-access mechanism matches
  actual behavior and documented scope.

## Notarization

Use this section only when the active release channel requires notarization:

1. Archive the signed app in the channel's supported container without changing
   its contents.
2. Submit with the current approved notarization tool and credentials supplied
   through an approved keychain profile or CI secret.
3. Retrieve and inspect the notarization log if submission is rejected.
4. Staple and validate the accepted ticket when the channel distributes a
   stapled artifact.
5. Run the channel-required Gatekeeper assessment and keep its result separate
   from code-signing verification.

Never place credentials, API keys, or notarization profiles in the repository.

## Release smoke test

- Test the exact artifact produced by the active release channel, not a later
  development build. Do not require a signed or stapled artifact when the
  current channel does not produce one.
- Prefer a clean macOS account without existing Scholium state.
- Derive smoke journeys from the current release gates and reachable product
  contract; do not keep a feature checklist here.
- Confirm current generated-state and unsupported-data preservation policies
  without deleting or rewriting unrelated research data.
- Re-run the active channel's verification if the smoke workflow or file
  provider attaches metadata to the bundle. Remove only approved nonsigned
  metadata; never repair a smoke-tested distribution artifact by re-signing it
  in place.

## Reporting boundary

Report channel, signing identity when applicable, architectures, channel-required
notarization or staple validation, Gatekeeper assessment when applicable, and
smoke-test scope separately. Do not collapse them into “release verified.”

## Source lineage

This workflow adapts release checkpoints from the MIT-licensed [Dimillian macOS SwiftPM packaging skill](https://github.com/Dimillian/Skills/tree/main/macos-spm-app-packaging) to Scholium's documented release boundary.
