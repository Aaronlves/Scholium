import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ScholiumFileSelectionError: LocalizedError, Equatable {
    case presenterUnavailable
    case selectionAlreadyInProgress
    case unusableSelection
    case wrongItemKind
    case rejectedSelection(message: String)

    var errorDescription: String? {
        switch self {
        case .presenterUnavailable:
            String(
                localized: "File selection is unavailable in this window.",
                table: "Localizable",
                bundle: .module
            )
        case .selectionAlreadyInProgress:
            String(
                localized: "Finish the current file selection before choosing another file or folder.",
                table: "Localizable",
                bundle: .module
            )
        case .unusableSelection:
            String(
                localized: "The file panel did not return a usable selection.",
                table: "Localizable",
                bundle: .module
            )
        case .wrongItemKind:
            String(
                localized: "Choose the requested kind of file or folder.",
                table: "Localizable",
                bundle: .module
            )
        case .rejectedSelection(let message):
            message
        }
    }
}

/// A typed native Open-panel request. It describes only the current selection
/// task; bookmarks, registration, importing, and later filesystem operations
/// remain with their workflow owners.
struct ScholiumFileSelectionRequest {
    enum SelectionKind {
        case files(
            allowedContentTypes: [UTType],
            allowsMultipleSelection: Bool = false,
            resolvesAliases: Bool = true
        )
        case directory(canCreateDirectories: Bool)
    }

    enum Constraint {
        case unrestricted
        case exactCanonicalDirectory(URL, rejectionMessage: String)
    }

    let title: String?
    let message: String?
    let prompt: String?
    let initialDirectoryURL: URL?
    let kind: SelectionKind
    let constraint: Constraint

    init(
        title: String? = nil,
        message: String? = nil,
        prompt: String? = nil,
        initialDirectoryURL: URL? = nil,
        kind: SelectionKind,
        constraint: Constraint = .unrestricted
    ) {
        self.title = title
        self.message = message
        self.prompt = prompt
        self.initialDirectoryURL = initialDirectoryURL
        self.kind = kind
        self.constraint = constraint
    }

    var allowsMultipleSelection: Bool {
        switch kind {
        case .files(_, let allowsMultipleSelection, _):
            allowsMultipleSelection
        case .directory:
            false
        }
    }

    @MainActor
    func makePanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = title ?? ""
        panel.message = message ?? ""
        if let prompt { panel.prompt = prompt }
        panel.directoryURL = initialDirectoryURL
        panel.allowsMultipleSelection = allowsMultipleSelection

        switch kind {
        case .files(let allowedContentTypes, _, let resolvesAliases):
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.canCreateDirectories = false
            panel.allowedContentTypes = allowedContentTypes
            panel.resolvesAliases = resolvesAliases
        case .directory(let canCreateDirectories):
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = canCreateDirectories
        }
        return panel
    }

    func validatedURLs(_ selectedURLs: [URL]) throws -> [URL] {
        guard !selectedURLs.isEmpty,
              allowsMultipleSelection || selectedURLs.count == 1 else {
            throw ScholiumFileSelectionError.unusableSelection
        }
        try selectedURLs.forEach(validateItemKind)

        switch constraint {
        case .unrestricted:
            return selectedURLs
        case .exactCanonicalDirectory(let expected, let rejectionMessage):
            guard selectedURLs.count == 1 else {
                throw ScholiumFileSelectionError.unusableSelection
            }
            let canonicalExpected = Self.canonicalDirectory(expected)
            let canonicalSelection = Self.canonicalDirectory(selectedURLs[0])
            guard canonicalSelection == canonicalExpected else {
                throw ScholiumFileSelectionError.rejectedSelection(
                    message: rejectionMessage
                )
            }
            return [canonicalExpected]
        }
    }

    private func validateItemKind(_ url: URL) throws {
        let inspectedURL: URL
        switch kind {
        case .files(_, _, let resolvesAliases):
            inspectedURL = resolvesAliases ? url.resolvingSymlinksInPath() : url
        case .directory:
            inspectedURL = url.resolvingSymlinksInPath()
        }
        let values: URLResourceValues
        do {
            values = try inspectedURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
            ])
        } catch {
            throw ScholiumFileSelectionError.unusableSelection
        }
        switch kind {
        case .files:
            guard values.isRegularFile == true else {
                throw ScholiumFileSelectionError.wrongItemKind
            }
        case .directory:
            guard values.isDirectory == true else {
                throw ScholiumFileSelectionError.wrongItemKind
            }
        }
    }

    private static func canonicalDirectory(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
}

/// One presenter per SwiftUI scene. It borrows that scene's exact NSWindow and
/// owns only the native panel lifetime; feature views retain selection intent,
/// error presentation, and all consequential work.
@MainActor
final class ScholiumFileSelectionPresenter: ObservableObject {
    private weak var window: NSWindow?
    private weak var activePanel: NSOpenPanel?
    // SwiftUI may attach a replacement bridge before removing its predecessor.
    // Only the bridge that established the current binding may tear it down.
    private var windowAttachmentID: UUID?

    fileprivate func attach(to window: NSWindow, attachmentID: UUID) {
        self.window = window
        windowAttachmentID = attachmentID
    }

    fileprivate func detach(attachmentID: UUID) {
        guard windowAttachmentID == attachmentID else { return }
        activePanel?.cancel(nil)
        activePanel = nil
        window = nil
        windowAttachmentID = nil
    }

    func selectURL(_ request: ScholiumFileSelectionRequest) async throws -> URL? {
        guard !request.allowsMultipleSelection else {
            throw ScholiumFileSelectionError.unusableSelection
        }
        return try await selectURLs(request)?.first
    }

    func selectURLs(_ request: ScholiumFileSelectionRequest) async throws -> [URL]? {
        guard let presentationWindow else {
            throw ScholiumFileSelectionError.presenterUnavailable
        }
        guard activePanel == nil else {
            throw ScholiumFileSelectionError.selectionAlreadyInProgress
        }

        let panel = request.makePanel()
        activePanel = panel
        defer {
            if activePanel === panel { activePanel = nil }
        }

        let response = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: presentationWindow) { response in
                    continuation.resume(returning: response)
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelActivePanel()
            }
        }
        try Task.checkCancellation()

        guard response == .OK else { return nil }
        return try request.validatedURLs(panel.urls)
    }

    var presentationWindow: NSWindow? {
        guard var candidate = window else { return nil }
        while let attachedSheet = candidate.attachedSheet {
            candidate = attachedSheet
        }
        return candidate
    }

    private func cancelActivePanel() {
        activePanel?.cancel(nil)
    }
}

private struct ScholiumFileSelectionPresenterKey: EnvironmentKey {
    static let defaultValue: ScholiumFileSelectionPresenter? = nil
}

extension EnvironmentValues {
    var scholiumFileSelectionPresenter: ScholiumFileSelectionPresenter? {
        get { self[ScholiumFileSelectionPresenterKey.self] }
        set { self[ScholiumFileSelectionPresenterKey.self] = newValue }
    }
}

extension View {
    /// Installs the one native file-selection owner for an entire scene.
    /// Apply this after the scene's presentation modifiers so their sheets
    /// inherit the presenter as well as the scene's ordinary content.
    func scholiumFileSelectionScene(
        presenter: ScholiumFileSelectionPresenter
    ) -> some View {
        environment(\.scholiumFileSelectionPresenter, presenter)
            .background(
                ScholiumFileSelectionWindowAttachment(presenter: presenter)
            )
    }
}

struct ScholiumFileSelectionWindowAttachment: NSViewRepresentable {
    let presenter: ScholiumFileSelectionPresenter

    func makeNSView(context: Context) -> ScholiumFileSelectionAttachmentView {
        let view = ScholiumFileSelectionAttachmentView()
        view.presenter = presenter
        return view
    }

    func updateNSView(
        _ nsView: ScholiumFileSelectionAttachmentView,
        context: Context
    ) {
        nsView.presenter = presenter
    }
}

final class ScholiumFileSelectionAttachmentView: NSView {
    private let attachmentID = UUID()
    weak var presenter: ScholiumFileSelectionPresenter? {
        didSet {
            guard oldValue !== presenter else { return }
            oldValue?.detach(attachmentID: attachmentID)
            if let window {
                presenter?.attach(to: window, attachmentID: attachmentID)
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            presenter?.attach(to: window, attachmentID: attachmentID)
        } else {
            presenter?.detach(attachmentID: attachmentID)
        }
    }
}

extension Optional where Wrapped == ScholiumFileSelectionPresenter {
    @MainActor
    func requiredForFileSelection() throws -> ScholiumFileSelectionPresenter {
        guard let self else {
            throw ScholiumFileSelectionError.presenterUnavailable
        }
        return self
    }
}
