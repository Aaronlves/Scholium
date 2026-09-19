import Foundation

/// What the machine running the tests can and cannot witness.
///
/// Most of this target's tests assert on real AppKit and WebKit behaviour, and
/// they are right to: Scholium is a native application and a Note's appearance
/// is part of its correctness. A few of them go further and need something a
/// shared runner does not have — a display of a working size, the bundled
/// typefaces registered with the font server, scroll bars configured the way a
/// Mac with a pointing device configures them.
///
/// Those tests are not flaky. They fail on such a machine for a reason that has
/// nothing to do with Scholium, and would keep failing however many times they
/// ran. Rather than loosen what they assert until a headless runner can pass
/// them, the runner declares that it cannot stand as a witness, and they are
/// reported as skipped. The evidence then has to come from `verify.sh` on a
/// development Mac, which is where it was always meaningful.
enum ScholiumTestEnvironment {
    /// False when the caller has declared it has no development Mac's display,
    /// fonts, or input devices — `SCHOLIUM_SKIP_DISPLAY_EVIDENCE=1`.
    static var providesDisplayEvidence: Bool {
        ProcessInfo.processInfo.environment["SCHOLIUM_SKIP_DISPLAY_EVIDENCE"] != "1"
    }
}
