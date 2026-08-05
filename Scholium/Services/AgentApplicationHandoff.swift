import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct RememberedAgentApplication: Codable, Equatable, Sendable {
    let displayName: String
    let bundleIdentifier: String?
    let bookmarkData: Data
}

enum AgentApplicationDisplayName {
    static func sanitized(_ candidate: String?, fallback: String = "Agent App") -> String {
        let normalized = (candidate ?? "")
            .components(separatedBy: .controlCharacters)
            .joined(separator: " ")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return fallback }
        return String(normalized.prefix(80))
    }
}

@MainActor
protocol AgentApplicationPreferencePersisting {
    func load() throws -> RememberedAgentApplication?
    func save(_ application: RememberedAgentApplication) throws
    func forget() throws
}

@MainActor
protocol AgentApplicationSystemProviding: AnyObject {
    func chooseApplication() throws -> URL?
    func makeReference(for url: URL) throws -> RememberedAgentApplication
    func openApplication(
        _ application: RememberedAgentApplication,
        completion: @escaping @MainActor (Error?) -> Void
    ) throws -> RememberedAgentApplication?
}

enum AgentApplicationHandoffError: LocalizedError {
    case invalidApplication
    case invalidPreference
    case noRememberedApplication
    case unsupportedPreference

    var errorDescription: String? {
        switch self {
        case .invalidApplication:
            String(localized: "Choose a macOS application.", table: "Localizable", bundle: .module)
        case .invalidPreference:
            String(localized: "The remembered agent application preference is invalid.", table: "Localizable", bundle: .module)
        case .noRememberedApplication:
            String(localized: "Choose an agent application before opening it.", table: "Localizable", bundle: .module)
        case .unsupportedPreference:
            String(localized: "The remembered agent application uses an unsupported preference format.", table: "Localizable", bundle: .module)
        }
    }
}

@MainActor
final class MacAgentApplicationSystem: AgentApplicationSystemProviding {
    func chooseApplication() throws -> URL? {
        let panel = NSOpenPanel()
        panel.title = ScholiumL10n.string("Choose Agent Application")
        panel.message = "Scholium will remember this application on this Mac. Non-secret connection instructions are copied, but never pasted or sent automatically. The Pairing Code remains separate in Scholium."
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.resolvesAliases = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    func makeReference(for url: URL) throws -> RememberedAgentApplication {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        try validateApplication(at: resolvedURL)
        return RememberedAgentApplication(
            displayName: displayName(for: resolvedURL),
            bundleIdentifier: Bundle(url: resolvedURL)?.bundleIdentifier,
            bookmarkData: try resolvedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: [.nameKey, .isApplicationKey],
                relativeTo: nil
            )
        )
    }

    func openApplication(
        _ application: RememberedAgentApplication,
        completion: @escaping @MainActor (Error?) -> Void
    ) throws -> RememberedAgentApplication? {
        var bookmarkIsStale = false
        let url = try URL(
            resolvingBookmarkData: application.bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &bookmarkIsStale
        ).resolvingSymlinksInPath().standardizedFileURL
        let isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
        do {
            try validateApplication(at: url)
            let refreshedReference = bookmarkIsStale ? try makeReference(for: url) : nil
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: configuration
            ) { _, error in
                if isAccessingSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
                Task { @MainActor in
                    completion(error)
                }
            }
            return refreshedReference
        } catch {
            if isAccessingSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
            throw error
        }
    }

    private func validateApplication(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [
            .isApplicationKey,
            .isReadableKey,
        ])
        guard values.isApplication == true, values.isReadable == true else {
            throw AgentApplicationHandoffError.invalidApplication
        }
    }

    private func displayName(for url: URL) -> String {
        let bundle = Bundle(url: url)
        let candidates = [
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
            url.deletingPathExtension().lastPathComponent,
        ]
        return candidates.lazy
            .map { AgentApplicationDisplayName.sanitized($0, fallback: "") }
            .first(where: { !$0.isEmpty })
            ?? "Agent App"
    }
}

@MainActor
final class AgentApplicationHandoffController: ObservableObject {
    @Published private(set) var rememberedApplication: RememberedAgentApplication?
    @Published private(set) var isOpening = false
    @Published private(set) var errorMessage: String?

    private let store: any AgentApplicationPreferencePersisting
    private let system: any AgentApplicationSystemProviding

    init(
        store: any AgentApplicationPreferencePersisting,
        system: any AgentApplicationSystemProviding
    ) {
        self.store = store
        self.system = system
        do {
            rememberedApplication = try store.load()
        } catch {
            rememberedApplication = nil
            errorMessage = String(localized: "Scholium could not restore the remembered agent application. Choose it again.", table: "Localizable", bundle: .module)
        }
    }

    convenience init(applicationSupportURL: URL) {
        self.init(
            store: FileAgentApplicationPreferenceStore(
                applicationSupportURL: applicationSupportURL
            ),
            system: MacAgentApplicationSystem()
        )
    }

    var primaryActionTitle: String {
        if let application = rememberedApplication {
            return String(
                localized: "Copy and Open \(application.displayName)…",
                table: "Localizable",
                bundle: .module
            )
        }
        return String(
            localized: "Copy and Choose Agent App…",
            table: "Localizable",
            bundle: .module
        )
    }

    var primaryActionAccessibilityHint: String {
        if let application = rememberedApplication {
            return String(
                localized: "Copies non-secret connection instructions, then opens \(application.displayName). You paste and submit them yourself; the Pairing Code remains separate in Scholium.",
                table: "Localizable",
                bundle: .module
            )
        }
        return String(
            localized: "Copies non-secret connection instructions, then asks you to choose an application to remember and open. You paste and submit them yourself; the Pairing Code remains separate in Scholium.",
            table: "Localizable",
            bundle: .module
        )
    }

    @discardableResult
    func copyAndOpen(
        instructions: String,
        copy: (String) throws -> Void
    ) -> Bool {
        guard copyInstructions(instructions, using: copy) else { return false }
        if rememberedApplication == nil {
            chooseApplication(openAfterSelection: true)
        } else {
            openRememberedApplication()
        }
        return true
    }

    @discardableResult
    func copyOnly(
        instructions: String,
        copy: (String) throws -> Void
    ) -> Bool {
        copyInstructions(instructions, using: copy)
    }

    func chooseApplication(openAfterSelection: Bool = false) {
        guard !isOpening else { return }
        errorMessage = nil
        do {
            guard let url = try system.chooseApplication() else { return }
            let application = try system.makeReference(for: url)
            try store.save(application)
            rememberedApplication = application
            if openAfterSelection {
                openRememberedApplication()
            }
        } catch {
            errorMessage = String(localized: "Scholium could not remember the selected application. \(error.localizedDescription)", table: "Localizable", bundle: .module)
        }
    }

    func openRememberedApplication() {
        guard !isOpening else { return }
        guard let application = rememberedApplication else {
            errorMessage = AgentApplicationHandoffError.noRememberedApplication.localizedDescription
            return
        }
        errorMessage = nil
        isOpening = true
        do {
            let refreshedReference = try system.openApplication(application) { [weak self] error in
                guard let self else { return }
                self.isOpening = false
                if let error {
                    self.errorMessage = String(localized: "Scholium could not open \(application.displayName). \(error.localizedDescription)", table: "Localizable", bundle: .module)
                }
            }
            if let refreshedReference {
                do {
                    try store.save(refreshedReference)
                    rememberedApplication = refreshedReference
                } catch {
                    errorMessage = String(localized: "Scholium could not refresh the remembered application reference. Choose the application again if opening fails.", table: "Localizable", bundle: .module)
                }
            }
        } catch {
            isOpening = false
            errorMessage = String(localized: "Scholium could not open \(application.displayName). Choose the application again. \(error.localizedDescription)", table: "Localizable", bundle: .module)
        }
    }

    func forgetApplication() {
        guard !isOpening else { return }
        errorMessage = nil
        do {
            try store.forget()
            rememberedApplication = nil
        } catch {
            errorMessage = String(localized: "Scholium could not forget the agent application. \(error.localizedDescription)", table: "Localizable", bundle: .module)
        }
    }

    private func copyInstructions(
        _ instructions: String,
        using copy: (String) throws -> Void
    ) -> Bool {
        errorMessage = nil
        do {
            try copy(instructions)
            return true
        } catch {
            errorMessage = String(localized: "Scholium could not copy the prepared instructions. \(error.localizedDescription)", table: "Localizable", bundle: .module)
            return false
        }
    }
}
