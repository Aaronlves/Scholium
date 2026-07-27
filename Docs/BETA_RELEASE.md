# Scholium source-first beta release

**Status:** Approved distribution policy; no external artifact has passed the
release gates yet.

## Release identity

- Git tag and public release label: `v0.1.0-beta.1`
- App marketing version: `0.1.0`
- App build number: `1`
- Minimum system: macOS 26
- Public binary: Scholium app only; its version-matched CLI is an embedded helper, not a separate beta asset
- Source license: `GPL-3.0-or-later`

The public GitHub release pairs the exact tagged source with an optional
ad-hoc-signed app ZIP. Developer ID signing and notarization are deferred
distribution improvements, not conditions for publishing the source.

## Required GitHub release assets

1. `Scholium-0.1.0-beta.1-macos-<architecture>.zip` containing only
   `Scholium.app`, including its signed `Contents/Helpers/scholium` helper.
2. The matching `.sha256` checksum file.
3. GitHub's source archives for the exact `v0.1.0-beta.1` tag.
4. Release notes stating the supported macOS version and verified architecture;
   claim universal support only after inspecting every executable and embedded
   native dependency.
5. `LICENSE`, `THIRD_PARTY_NOTICES.md`, and the applicable full third-party
   license texts inside the app bundle.

Keep binary and source equally discoverable on one release page. Exclude any
separate CLI asset, real vault, Application Support state, signing credential,
bookmark, index, or research content.

## Installation for an unsigned beta

Testers do not need Xcode:

1. Download the ZIP from the GitHub release and expand it.
2. Move **Scholium** to Applications.
3. Try to open Scholium once. macOS will block the unidentified developer.
4. Open **System Settings → Privacy & Security**, scroll to Security, choose
   **Open Anyway**, authenticate, and confirm **Open**.
5. If an external agent will use Scholium, open **Scholium → Settings →
   Research Guidance → Skills → Advanced → Scholium CLI**, choose **Install**,
   and follow the displayed PATH guidance if `~/.local/bin` is not already
   discoverable. The app installs its version-matched helper; no separate CLI
   download or Xcode build is required.

Release notes must state that the beta lacks Developer ID signing and
notarization, so macOS cannot perform its normal publisher and malware checks.
Testers should use only the project's GitHub release and verify SHA-256. Never
instruct them to disable Gatekeeper, remove quarantine recursively, or install
an untrusted root certificate; managed Macs may prohibit the override.

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
   app metadata, canonical D-097 application icon, other resources,
   entitlements, architecture, ad-hoc signature, ZIP, and checksum.
5. Smoke-test the exact expanded ZIP in a clean macOS account without existing
   Scholium state. Verify the canonical icon in Finder and the Dock at ordinary
   and small sizes. Exercise first launch, Triptych selection, read/edit/save,
   conflicts, Search, all three Research Inspector modes and a representative
   Research Action, checkpoints, restoration, and unavailable optional
   integrations.
6. Complete applicable specification gates and record every waiver or known
   limitation. Never report an ad-hoc signature as Developer ID signing,
   notarization, or Gatekeeper acceptance.
7. Run the approved packaged-app G7 protocol in
   `PERFORMANCE_BENCHMARK.md` against frozen RDF-1 on Reference Machine R1 and
   retain its raw 30-sample artifacts. Internal Swift microbenchmarks are not
   a substitute for this release gate.

No real vault file may be opened or modified during release verification.

## Optional future signed distribution

If an eligible organization sponsors Scholium or the project funds Apple
Developer Program membership, rebuild the exact release commit with a
Developer ID Application certificate, notarize and staple before archiving,
then repeat the complete smoke test. Never re-sign the tested ad-hoc artifact
or share a certificate private key outside its responsible organization.
