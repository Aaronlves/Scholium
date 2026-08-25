import AppKit
import Foundation
import ScholiumApplication
import ScholiumContracts
import SwiftUI

struct ApplicationStorageFailure: Equatable, Sendable {
    let summary: String
    let details: String
}

struct ApplicationRegistryRecovery: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case triptych(WorkspaceRegistryHealth, registryURL: URL)
    }

    let source: Source
    let recoveryFailure: String?

    var summary: String {
        switch source {
        case .triptych(let health, _): health.summary
        }
    }

    var title: LocalizedStringResource {
        switch source {
        case .triptych: "Triptych Registry Needs Repair"
        }
    }

    var canRelinkAfterPreserving: Bool {
        switch source {
        case .triptych(let health, _): health.canRelinkAfterPreserving
        }
    }

    var details: String {
        var lines: [String]
        switch source {
        case .triptych(let health, let registryURL):
            lines = [health.details, "Registry location: \(registryURL.path)"]
        }
        if let recoveryFailure {
            lines.append("Recovery could not preserve the original file: \(recoveryFailure)")
        }
        return lines.joined(separator: "\n\n")
    }

    func recordingFailure(_ error: Error) -> Self {
        let updatedSource: Source
        switch source {
        case .triptych(_, let registryURL):
            let currentHealth: WorkspaceRegistryHealth
            if let registryError = error as? WorkspaceRegistryError,
               case .registryRecoveryRequired(let observedHealth) = registryError {
                currentHealth = observedHealth
            } else {
                currentHealth = .ioFailure(error.localizedDescription)
            }
            updatedSource = .triptych(currentHealth, registryURL: registryURL)
        }
        return Self(
            source: updatedSource,
            recoveryFailure: error.localizedDescription
        )
    }
}

enum ApplicationBootstrapState {
    case starting
    case ready(WorkspaceStore)
    case storageUnavailable(ApplicationStorageFailure)
    case registryRecovery(ApplicationRegistryRecovery)
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
            var resolvedStorageURL: URL?
            do {
                let url = try resolver()
                resolvedStorageURL = url
                let store = try WorkspaceStore(applicationSupportURL: url)
                guard self.attempt == currentAttempt else {
                    await store.shutdownApplicationRuntime()
                    return
                }
                state = .ready(store)
            } catch let error as WorkspaceRegistryError {
                guard self.attempt == currentAttempt else { return }
                switch error {
                case .registryRecoveryRequired(let health):
                    guard let resolvedStorageURL else {
                        state = .storageUnavailable(ApplicationStorageFailure(
                            summary: String(localized:
                                "Scholium cannot establish its Application Support storage."
                            ),
                            details: error.localizedDescription
                        ))
                        return
                    }
                    let registryURL = resolvedStorageURL
                        .standardizedFileURL
                        .appendingPathComponent("Workspace", isDirectory: true)
                        .appendingPathComponent("workspace-registration-v3.json")
                    state = .registryRecovery(ApplicationRegistryRecovery(
                        source: .triptych(health, registryURL: registryURL),
                        recoveryFailure: nil
                    ))
                default:
                    state = .storageUnavailable(ApplicationStorageFailure(
                        summary: String(localized:
                            "Scholium cannot establish its Application Support storage."
                        ),
                        details: error.localizedDescription
                    ))
                }
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

    func repairRegistryAndRetry() {
        guard case .registryRecovery(let recovery) = state,
              recovery.canRelinkAfterPreserving else { return }
        do {
            switch recovery.source {
            case .triptych(_, let registryURL):
                _ = try WorkspaceRegistryRecoveryOperations
                    .preserveMalformedRegistryForRelinking(
                        storageURL: registryURL.deletingLastPathComponent()
                    )
            }
            retry()
        } catch {
            state = .registryRecovery(recovery.recordingFailure(error))
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
    let content: Content

    init(
        controller: ApplicationBootstrapController,
        @ViewBuilder content: () -> Content
    ) {
        self.controller = controller
        self.content = content()
    }

    var body: some View {
        Group {
            switch controller.state {
            case .starting:
                ScholiumLaunchPlaceholderView()
            case .ready(let store):
                content.environmentObject(store)
            case .storageUnavailable(let failure):
                ApplicationStorageUnavailableView(
                    failure: failure,
                    retry: controller.retry
                )
            case .registryRecovery(let recovery):
                ApplicationRegistryRecoveryView(
                    recovery: recovery,
                    retry: controller.retry,
                    relink: controller.repairRegistryAndRetry
                )
            }
        }
        .task { controller.startIfNeeded() }
    }
}

private struct ApplicationRegistryRecoveryView: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    let recovery: ApplicationRegistryRecovery
    let retry: () -> Void
    let relink: () -> Void
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Onboarding.rootSectionSpacing) {
            Text(recovery.title)
                .font(ScholiumTypography.interface(.primaryTitle))
                .accessibilityAddTraits(.isHeader)
            Text(recovery.summary)
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)

            Button {
                showsDetails.toggle()
            } label: {
                HStack(spacing: ScholiumMetrics.Onboarding.rootDisclosureSpacing) {
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .rotationEffect(.degrees(showsDetails ? 90 : 0))
                        .animation(
                            ScholiumMotion.disclosure(reduceMotion: reduceMotion),
                            value: showsDetails
                        )
                    Text("Details")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details")
            .accessibilityValue(showsDetails ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows the registry diagnostic and recovery location.")

            if showsDetails {
                Text(recovery.details)
                    .font(ScholiumTypography.exact(.body))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("scholium.registryRecovery.details")
            }

            HStack {
                Button("Quit") { NSApplication.shared.terminate(nil) }
                Spacer()
                if recovery.canRelinkAfterPreserving {
                    Button("Relink Triptych", action: relink)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint(
                            "Preserves the damaged registry, then opens Triptych setup so you can choose the three folders again."
                        )
                } else {
                    Button("Retry", action: retry)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint("Attempts to read the Triptych registry again.")
                }
            }
        }
        .padding(ScholiumMetrics.Onboarding.rootContentInset)
        .frame(width: 520, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                ApplicationStorageUnavailableWindowSizer(
                    contentSize: geometry.size
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.registryRecovery")
    }
}

private struct ApplicationStorageUnavailableView: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    let failure: ApplicationStorageFailure
    let retry: () -> Void
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Onboarding.rootSectionSpacing) {
            Text("Storage Unavailable")
                .font(ScholiumTypography.interface(.primaryTitle))
                .accessibilityAddTraits(.isHeader)
            Text(failure.summary)
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)

            Button {
                showsDetails.toggle()
            } label: {
                HStack(spacing: ScholiumMetrics.Onboarding.rootDisclosureSpacing) {
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .rotationEffect(.degrees(showsDetails ? 90 : 0))
                        .animation(
                            ScholiumMotion.disclosure(reduceMotion: reduceMotion),
                            value: showsDetails
                        )
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
                    .font(ScholiumTypography.exact(.body))
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
        .padding(ScholiumMetrics.Onboarding.rootContentInset)
        .frame(width: 520, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                ApplicationStorageUnavailableWindowSizer(
                    contentSize: geometry.size
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.storageUnavailable")
    }
}

/// Storage recovery is a compact root state, not a 720 × 720 onboarding page.
/// Keep the scene's canonical Bootstrap default for the ready path, resize only
/// while this failure view exists, and restore the exact prior frame on Retry.
private struct ApplicationStorageUnavailableWindowSizer: NSViewRepresentable {
    let contentSize: CGSize

    func makeNSView(context: Context) -> StorageUnavailableWindowSizingView {
        let view = StorageUnavailableWindowSizingView()
        view.desiredContentSize = contentSize
        return view
    }

    func updateNSView(
        _ nsView: StorageUnavailableWindowSizingView,
        context: Context
    ) {
        nsView.desiredContentSize = contentSize
    }

    static func dismantleNSView(
        _ nsView: StorageUnavailableWindowSizingView,
        coordinator: Void
    ) {
        nsView.restoreOriginalFrame()
    }
}

private final class StorageUnavailableWindowSizingView: NSView {
    var desiredContentSize: CGSize = .zero {
        didSet { scheduleDesiredContentSize() }
    }

    private weak var sizedWindow: NSWindow?
    private var originalFrame: NSRect?
    private var pendingResize: DispatchWorkItem?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleDesiredContentSize()
    }

    func restoreOriginalFrame() {
        pendingResize?.cancel()
        pendingResize = nil
        guard let sizedWindow, let originalFrame else { return }
        self.sizedWindow = nil
        self.originalFrame = nil
        DispatchQueue.main.async { [weak sizedWindow] in
            sizedWindow?.setFrame(originalFrame, display: true, animate: false)
        }
    }

    private func scheduleDesiredContentSize() {
        pendingResize?.cancel()
        let resize = DispatchWorkItem { [weak self] in
            self?.applyDesiredContentSize()
        }
        pendingResize = resize
        DispatchQueue.main.async(execute: resize)
    }

    private func applyDesiredContentSize() {
        pendingResize = nil
        guard let window,
              desiredContentSize.width > 0,
              desiredContentSize.height > 0 else { return }
        if sizedWindow !== window {
            restoreOriginalFrame()
            sizedWindow = window
            originalFrame = window.frame
        }

        let targetFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: desiredContentSize)
        ).size
        let currentFrame = window.frame
        guard abs(currentFrame.width - targetFrameSize.width) > 0.5
                || abs(currentFrame.height - targetFrameSize.height) > 0.5 else {
            return
        }
        let targetFrame = NSRect(
            x: currentFrame.midX - targetFrameSize.width / 2,
            y: currentFrame.maxY - targetFrameSize.height,
            width: targetFrameSize.width,
            height: targetFrameSize.height
        )
        window.setFrame(targetFrame, display: true, animate: false)
    }
}
