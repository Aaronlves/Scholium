import AppKit

/// SwiftPM owns the test runner and exit status; AppKit owns native event dispatch
/// for the remainder of this test process once an interaction requires it.
@MainActor
enum AppKitTestApplication {
    private static let startup = Task<Void, Never> { @MainActor in
        await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
            RunLoop.main.perform {
                MainActor.assumeIsolated {
                    precondition(NSApplication.shared.setActivationPolicy(.regular))
                    NSApplication.shared.activate()
                    ready.resume()
                    NSApplication.shared.run()
                    preconditionFailure("The AppKit test host stopped before the Swift Testing runner finished.")
                }
            }
        }
    }

    static func start() async {
        guard !NSApplication.shared.isRunning else { return }
        await startup.value
    }
}
