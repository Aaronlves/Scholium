# Scholium source-first beta release

**Status:** Approved distribution policy; no external artifact has passed the
release gates yet.

## Release identity

- Git tag and public release label: `v0.1.0-beta.1`
- App marketing version: `0.1.0`
- App build number: `1`
- Minimum system: macOS 26
- Public binary: Scholium app only; the `scholium` CLI is not a beta asset
- Source license: `GPL-3.0-or-later`

The public GitHub release is source-first. It provides the exact tagged source
and an optional convenience ZIP containing an ad-hoc-signed app. Developer ID
signing and Apple notarization are deferred until institutional sponsorship or
sufficient demand makes them practical. They are optional future distribution
improvements, not conditions for publishing the source.

## Required GitHub release assets

1. `Scholium-0.1.0-beta.1-macos-<architecture>.zip` containing only
   `Scholium.app`.
2. The matching `.sha256` checksum file.
3. GitHub's source archives for the exact `v0.1.0-beta.1` tag.
4. Release notes stating the supported macOS version and verified
   architecture. Do not claim universal support unless every executable and
   embedded native dependency has been inspected.
5. `LICENSE`, `THIRD_PARTY_NOTICES.md`, and the applicable full third-party
   license texts inside the app bundle.

The binary and corresponding source must remain equally easy to find from the
same release page. No CLI executable, real vault, local Application Support
state, signing credential, bookmark, index, or research content belongs in a
release asset.

## Installation for an unsigned beta

Testers do not need Xcode:

1. Download the ZIP from the GitHub release and expand it.
2. Move **Scholium** to Applications.
3. Try to open Scholium once. macOS will block the unidentified developer.
4. Open **System Settings → Privacy & Security**, scroll to Security, choose
   **Open Anyway**, authenticate, and confirm **Open**.

The release notes must explain that the beta is not Developer ID signed or
notarized and that macOS cannot perform Apple's normal publisher and malware
verification. Testers should download only from the project's GitHub release
and compare the SHA-256 checksum. Never instruct testers to disable Gatekeeper,
remove quarantine recursively, or install an untrusted root certificate.
Managed university or workplace Macs may prohibit the override.

## Release gates

Before creating the tag or uploading assets:

1. Freeze a reviewed commit and require a clean worktree for packaging.
2. Audit the current tree and Git history for credentials, personal research,
   private fixtures, bookmarks, generated indexes, local state, and identifying
   absolute paths.
3. Run the repository verification using disposable fixtures only:

   ```bash
   developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
   DEVELOPER_DIR="$developer_dir" ./Tools/Scripts/verify.sh
   ```
4. Package outside the checkout with `SCHOLIUM_REQUIRE_CLEAN=1` and inspect the
   app metadata, resources, entitlements, architecture, ad-hoc signature, ZIP,
   and checksum.
5. Smoke-test the exact expanded ZIP in a clean macOS account without existing
   Scholium state. Exercise first launch, Triptych selection, read/edit/save,
   conflicts, Search, Scholia, checkpoints, restoration, and unavailable
   optional integrations.
6. Complete the applicable PRD quality gates and record every waiver or known
   limitation. An ad-hoc signature must never be reported as Developer ID
   signing, notarization, or Gatekeeper acceptance.
7. Run the approved packaged-app G7 protocol in
   `PERFORMANCE_BENCHMARK.md` against frozen RDF-1 on Reference Machine R1 and
   retain its raw 30-sample artifacts. Internal Swift microbenchmarks are not
   a substitute for this release gate.

No real vault file may be opened or modified during release verification.

## Optional future signed distribution

If an eligible university or other organization sponsors Scholium, or the
project later funds Apple Developer Program membership, rebuild the exact
release commit with a Developer ID Application certificate, notarize and
staple the app before archiving it, and repeat the complete smoke test. Never
re-sign the already tested ad-hoc artifact and never share a certificate private
key outside its responsible organization.
