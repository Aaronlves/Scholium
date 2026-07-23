import AppKit
import Foundation
import ScholiumApplication
import SwiftUI

struct ApplicationStorageFailure: Equatable, Sendable {
    let summary: String
    let details: String
}

enum ApplicationBootstrapState {
    case starting
    case ready(WorkspaceStore)
    case storageUnavailable(ApplicationStorageFailure)
}

/// Resolves and validates the one real machine-state root before any
/// Workspace runtime exists. Retry always performs a fresh resolution.
@MainActor
final class ApplicationBootstrapController: ObservableObject {
    typealias Resolver = @MainActor () throws -> URL

    @Published private(set) var state: ApplicationBootstrapState = .starting

    private let resolver: Resolver
    private var attempt: UInt64 = 0

    init(
        resolver: @escaping Resolver = {
            try ApplicationBootstrapController.resolveStorageURL()
        }
    ) {
        self.resolver = resolver
    }

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    func startIfNeeded() {
        guard attempt == 0 else { return }
        retry()
    }

    func retry() {
        guard attempt < UInt64.max else {
            state = .storageUnavailable(ApplicationStorageFailure(
                summary: String(localized:
                    "Scholium cannot establish its Application Support storage."
                ),
                details: "Storage retry attempt IDs were exhausted."
            ))
            return
        }
        attempt += 1
        let currentAttempt = attempt
        state = .starting
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.attempt == currentAttempt else { return }
            do {
                let url = try resolver()
                let store = try WorkspaceStore(applicationSupportURL: url)
                guard self.attempt == currentAttempt else {
                    await store.shutdownApplicationRuntime()
                    return
                }
                state = .ready(store)
            } catch {
                guard self.attempt == currentAttempt else { return }
                state = .storageUnavailable(ApplicationStorageFailure(
                    summary: String(localized:
                        "Scholium cannot establish its Application Support storage."
                    ),
                    details: error.localizedDescription
                ))
            }
        }
    }

    static func resolveStorageURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws -> URL {
        if let isolatedHome = ScholiumRuntimeIsolation.homeURL(
            environment: environment,
            bundleIdentifier: bundleIdentifier
        ) {
            return isolatedHome.appendingPathComponent(
                "ApplicationSupport",
                isDirectory: true
            )
        }
#if DEBUG
        if bundleIdentifier == ScholiumRuntimeIsolation.qaBundleIdentifier {
            throw CocoaError(.fileNoSuchFile)
        }
#endif
        return try ScholiumPaths.sharedApplicationSupportURL()
    }
}

struct ApplicationBootstrapGate<Content: View>: View {
    @ObservedObject var controller: ApplicationBootstrapController
    @ViewBuilder let content: (WorkspaceStore) -> Content

    var body: some View {
        Group {
            switch controller.state {
            case .starting:
                ScholiumLaunchPlaceholderView()
            case .ready(let store):
                content(store)
            case .storageUnavailable(let failure):
                ApplicationStorageUnavailableView(
                    failure: failure,
                    retry: controller.retry
                )
            }
        }
        .task { controller.startIfNeeded() }
    }
}

private struct ApplicationStorageUnavailableView: View {
    let failure: ApplicationStorageFailure
    let retry: () -> Void
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Storage Unavailable")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(failure.summary)
                .foregroundStyle(.secondary)

            Button {
                showsDetails.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showsDetails ? "chevron.down" : "chevron.right")
                        .imageScale(.small)
                    Text("Details")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details")
            .accessibilityValue(showsDetails ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows the storage error details.")

            if showsDetails {
                Text(failure.details)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("scholium.storageUnavailable.details")
            }

            HStack {
                Button("Quit") { NSApplication.shared.terminate(nil) }
                Spacer()
                Button("Retry", action: retry)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Attempts to establish Application Support storage again.")
            }
        }
        .padding(28)
        .frame(minWidth: 440, idealWidth: 520, maxWidth: 620)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.storageUnavailable")
    }
}
