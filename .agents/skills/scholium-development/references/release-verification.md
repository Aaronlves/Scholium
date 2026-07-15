# Scholium release verification

Use this checklist for distribution work beyond the existing ad-hoc package. Preserve `com.kbmanager.app` until the migration plan explicitly authorizes an identity change.

## Build and package

1. Record the clean worktree or exact uncommitted state being released.
2. Run `./Tools/Scripts/verify.sh` and `./Tools/Scripts/package-app.sh` with the intended toolchain and signing identity.
3. Confirm the app bundle contains the executable, processed SwiftPM resource bundle, icon, and intended `Info.plist` values.
4. Verify both artifacts in `${SCHOLIUM_PACKAGE_OUTPUT:-${HOME}/Applications/Scholium Builds}`; the standalone CLI is a separate signed artifact. Never direct release output into the source checkout.
5. Inspect architectures with `lipo -info` or `file`. Do not claim universal support unless every executable and embedded native dependency contains both required slices.

## Signing

- Use a real Developer ID identity for distribution; ad-hoc signing is only a local-development result.
- Keep hardened runtime enabled.
- Inspect the final signature, designated requirement, and entitlements with `codesign -d --verbose=4` and `codesign -d --entitlements :-`.
- Run strict verification after all bundle mutations. Removing only the approved Finder or File Provider extended attributes handled by `Tools/Scripts/package-app.sh` does not change signed contents, but still requires strict re-verification. Do not modify or re-sign distribution contents after signing except for notarization stapling; if signed contents change, rebuild and repeat signing and notarization.
- Confirm sandbox, user-selected read/write access, and app-scoped bookmark entitlements still match actual behavior.

## Notarization

1. Archive the signed app in a notarization-supported container without changing its contents.
2. Submit with `xcrun notarytool submit ... --wait` using credentials supplied through an approved keychain profile or CI secret.
3. Retrieve and inspect the notarization log if the submission is rejected.
4. Staple the accepted ticket with `xcrun stapler staple` and verify it with `xcrun stapler validate`.
5. Run `spctl --assess --type execute --verbose` on the stapled app. Treat Gatekeeper failure as unresolved even if `codesign --verify` passes.

Never place credentials, API keys, or notarization profiles in the repository.

## Release smoke test

- Test the exact signed and stapled artifact, not a later development build.
- Prefer a clean macOS account without existing Scholium state.
- Verify first launch, vault selection and bookmark restoration, read/edit/save conflict handling, search, relationships, canvas state, Zotero unavailability, proposal review, and CLI help.
- Confirm generated state remains outside the vault and legacy migration does not delete old data.
- Re-run signature verification if the smoke workflow or file provider attaches metadata to the bundle. Remove only approved nonsigned metadata; never repair a smoke-tested distribution artifact by re-signing it in place.

## Reporting boundary

Report signing identity, architectures, notarization result, staple validation, Gatekeeper assessment, and smoke-test scope separately. Do not collapse them into “release verified.”

## Source lineage

This workflow adapts release checkpoints from the MIT-licensed [Dimillian macOS SwiftPM packaging skill](https://github.com/Dimillian/Skills/tree/main/macos-spm-app-packaging) to Scholium's existing scripts, sandbox entitlements, CLI artifact, and migration-sensitive bundle identity.
