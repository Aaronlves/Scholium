import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Library creation destination")
@MainActor
struct DiscoveryLibraryCreationTests {
    @Test("Creation uses only one exact current folder without changing selection or document presentation")
    func exactSelectedFolder() {
        let shell = WindowShellState()
        let controller = DiscoveryController(shellState: shell)
        let scope = LibraryDisclosureScope(vaultID: UUID(), sourceScope: .library)
        controller.setLibrarySelection(["Research/论证"], in: scope)
        let library = controller.library
        let inspector = shell.inspector

        #expect(controller.libraryCreationFolder(in: scope, availableFolders: ["Research", "Research/论证"]) == "Research/论证")
        #expect(controller.library == library)
        #expect(shell.inspector == inspector)
    }

    @Test("Root, Note, mixed, multiple, stale, and protected selections create at the vault root")
    func invalidFolderSelectionUsesRoot() {
        let controller = DiscoveryController()
        let scope = LibraryDisclosureScope(vaultID: UUID(), sourceScope: .library)
        let selections: [Set<String>] = [[], ["Note.md"], ["Research", "Note.md"], ["Research", "Other"], ["Removed"], ["Attachments"]]
        for selection in selections {
            controller.setLibrarySelection(selection, in: scope)
            #expect(controller.libraryCreationFolder(in: scope, availableFolders: ["Research", "Other", "Attachments"]) == nil)
            #expect(controller.librarySelection(in: scope) == selection)
        }
        #expect(controller.libraryCreationFolder(in: nil, availableFolders: ["Research"]) == nil)
    }

    @Test("Another role or vault cannot inherit the previous selected-folder destination")
    func scopeChangesKeepDestinationsIndependent() {
        let shell = WindowShellState()
        let controller = DiscoveryController(shellState: shell)
        let analyses = LibraryDisclosureScope(vaultID: UUID(), sourceScope: .library)
        let topics = LibraryDisclosureScope(vaultID: UUID(), sourceScope: .library)
        controller.setLibrarySelection(["Research"], in: analyses)
        #expect(controller.libraryCreationFolder(in: topics, availableFolders: ["Research"]) == nil)

        shell.selectLibraryWorkspace(.topicKnowledge)
        #expect(controller.libraryCreationFolder(in: topics, availableFolders: ["Research"]) == nil)
        controller.setLibrarySelection(["Concepts"], in: topics)
        #expect(controller.libraryCreationFolder(in: topics, availableFolders: ["Research", "Concepts"]) == "Concepts")

        shell.selectLibraryWorkspace(.paperAnalysis)
        #expect(controller.libraryCreationFolder(in: analyses, availableFolders: ["Research", "Concepts"]) == "Research")
        #expect(controller.libraryCreationFolder(in: analyses, availableFolders: []) == nil)
    }
}
