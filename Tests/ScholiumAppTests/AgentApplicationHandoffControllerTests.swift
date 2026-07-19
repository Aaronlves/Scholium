import Foundation
import Testing
@testable import ScholiumApp

@Suite("Agent application handoff")
@MainActor
struct AgentApplicationHandoffControllerTests {
    @Test("First handoff copies before choosing, remembering, and opening")
    func firstHandoffIsCopyFirst() throws {
        let store = MemoryAgentApplicationPreferenceStore()
        let system = FakeAgentApplicationSystem()
        system.selectedURL = URL(fileURLWithPath: "/Applications/Codex.app")
        system.referenceToMake = fixtureApplication(name: "Codex")
        let controller = AgentApplicationHandoffController(store: store, system: system)
        var copiedText: String?

        let copied = controller.copyAndOpen(instructions: "prepared packet") { text in
            copiedText = text
            #expect(system.chooseCount == 0)
        }

        #expect(copied)
        #expect(copiedText == "prepared packet")
        #expect(system.chooseCount == 1)
        #expect(system.openedApplications.map(\.displayName) == ["Codex"])
        #expect(store.savedApplications.map(\.displayName) == ["Codex"])
        #expect(controller.rememberedApplication?.displayName == "Codex")
        #expect(controller.errorMessage == nil)
    }

    @Test("Cancelling first selection preserves the completed copy")
    func cancelledSelectionPreservesCopy() {
        let store = MemoryAgentApplicationPreferenceStore()
        let system = FakeAgentApplicationSystem()
        let controller = AgentApplicationHandoffController(store: store, system: system)
        var copyCount = 0

        let copied = controller.copyAndOpen(instructions: "prepared packet") { _ in
            copyCount += 1
        }

        #expect(copied)
        #expect(copyCount == 1)
        #expect(system.chooseCount == 1)
        #expect(system.openedApplications.isEmpty)
        #expect(store.savedApplications.isEmpty)
        #expect(controller.rememberedApplication == nil)
        #expect(controller.errorMessage == nil)
    }

    @Test("A copy failure never chooses or opens an application")
    func copyFailureStopsHandoff() {
        let remembered = fixtureApplication(name: "Codex")
        let store = MemoryAgentApplicationPreferenceStore(loadedApplication: remembered)
        let system = FakeAgentApplicationSystem()
        let controller = AgentApplicationHandoffController(store: store, system: system)

        let copied = controller.copyAndOpen(instructions: "prepared packet") { _ in
            throw FixtureError.copyFailed
        }

        #expect(!copied)
        #expect(system.chooseCount == 0)
        #expect(system.openedApplications.isEmpty)
        #expect(controller.errorMessage?.contains("copy") == true)
    }

    @Test("Choosing another application remembers it without launching it")
    func choosingAnotherApplicationDoesNotLaunch() {
        let original = fixtureApplication(name: "Codex")
        let replacement = fixtureApplication(name: "Terminal")
        let store = MemoryAgentApplicationPreferenceStore(loadedApplication: original)
        let system = FakeAgentApplicationSystem()
        system.selectedURL = URL(fileURLWithPath: "/Applications/Terminal.app")
        system.referenceToMake = replacement
        let controller = AgentApplicationHandoffController(store: store, system: system)

        controller.chooseApplication()

        #expect(controller.rememberedApplication == replacement)
        #expect(store.savedApplications.last == replacement)
        #expect(system.openedApplications.isEmpty)
    }

    @Test("Opening failure leaves the remembered application recoverable")
    func openingFailurePreservesPreference() {
        let remembered = fixtureApplication(name: "Codex")
        let store = MemoryAgentApplicationPreferenceStore(loadedApplication: remembered)
        let system = FakeAgentApplicationSystem()
        system.openError = FixtureError.openFailed
        let controller = AgentApplicationHandoffController(store: store, system: system)

        controller.openRememberedApplication()

        #expect(controller.rememberedApplication == remembered)
        #expect(controller.errorMessage?.contains("could not open Codex") == true)
        #expect(!controller.isOpening)
    }

    @Test("Forget removes only the machine-local application preference")
    func forgetApplication() {
        let remembered = fixtureApplication(name: "Codex")
        let store = MemoryAgentApplicationPreferenceStore(loadedApplication: remembered)
        let controller = AgentApplicationHandoffController(
            store: store,
            system: FakeAgentApplicationSystem()
        )

        controller.forgetApplication()

        #expect(store.forgetCount == 1)
        #expect(controller.rememberedApplication == nil)
    }

    @Test("File preference survives reload and is removed explicitly")
    func filePreferenceRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-agent-app-preference-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let application = fixtureApplication(name: "Codex")
        let first = FileAgentApplicationPreferenceStore(applicationSupportURL: root)

        try first.save(application)

        let second = FileAgentApplicationPreferenceStore(applicationSupportURL: root)
        #expect(try second.load() == application)
        let fileURL = root.appendingPathComponent("AgentApplicationHandoff.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)

        try second.forget()
        #expect(try second.load() == nil)
    }

    @Test("External application names are bounded and single-line")
    func applicationDisplayNameIsSafeForPresentation() {
        let unsafe = "  Codex\n\u{0000}  " + String(repeating: "Agent", count: 30)
        let sanitized = AgentApplicationDisplayName.sanitized(unsafe)

        #expect(!sanitized.contains("\n"))
        #expect(!sanitized.contains("\u{0000}"))
        #expect(sanitized.hasPrefix("Codex Agent"))
        #expect(sanitized.count == 80)
    }

    private func fixtureApplication(name: String) -> RememberedAgentApplication {
        RememberedAgentApplication(
            displayName: name,
            bundleIdentifier: "fixture.\(name.lowercased())",
            bookmarkData: Data("bookmark-\(name)".utf8)
        )
    }
}

@MainActor
private final class MemoryAgentApplicationPreferenceStore: AgentApplicationPreferencePersisting {
    var loadedApplication: RememberedAgentApplication?
    private(set) var savedApplications: [RememberedAgentApplication] = []
    private(set) var forgetCount = 0

    init(loadedApplication: RememberedAgentApplication? = nil) {
        self.loadedApplication = loadedApplication
    }

    func load() throws -> RememberedAgentApplication? {
        loadedApplication
    }

    func save(_ application: RememberedAgentApplication) throws {
        savedApplications.append(application)
        loadedApplication = application
    }

    func forget() throws {
        forgetCount += 1
        loadedApplication = nil
    }
}

@MainActor
private final class FakeAgentApplicationSystem: AgentApplicationSystemProviding {
    var selectedURL: URL?
    var referenceToMake: RememberedAgentApplication?
    var refreshedReference: RememberedAgentApplication?
    var openError: Error?
    private(set) var chooseCount = 0
    private(set) var openedApplications: [RememberedAgentApplication] = []

    func chooseApplication() throws -> URL? {
        chooseCount += 1
        return selectedURL
    }

    func makeReference(for url: URL) throws -> RememberedAgentApplication {
        guard let referenceToMake else { throw FixtureError.invalidFixture }
        return referenceToMake
    }

    func openApplication(
        _ application: RememberedAgentApplication,
        completion: @escaping @MainActor (Error?) -> Void
    ) throws -> RememberedAgentApplication? {
        openedApplications.append(application)
        completion(openError)
        return refreshedReference
    }
}

private enum FixtureError: LocalizedError {
    case copyFailed
    case openFailed
    case invalidFixture

    var errorDescription: String? {
        switch self {
        case .copyFailed: "Fixture clipboard failure."
        case .openFailed: "Fixture launch failure."
        case .invalidFixture: "Fixture application reference is missing."
        }
    }
}
