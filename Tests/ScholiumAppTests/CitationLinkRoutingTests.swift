import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Citation link navigation boundaries")
@MainActor
struct CitationLinkRoutingTests {
    @Test("Reserved citation targets cannot enter Note navigation or report a broken Connection")
    func citationTargetsDoNotBecomeNoteLinks() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/citation-link-routing/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        let window = WindowModel(workspaceStore: store)
        for target in ["cite:missing", "CiTe:invalid field", " \nCITE:bad%ZZ\t", "scholium-zotero:unsupported"] {
            window.openInternalLink(target, from: "Synthetic.md")
        }
        #expect(window.shellState.operationIssues.isEmpty)
        #expect(window.currentDocumentDescriptor == nil)
        #expect(window.documentController.sourceLocationRequest == nil)
        await store.shutdownApplicationRuntime()
    }

    @Test("Reserved citation destinations never dispatch to an external application")
    func citationDestinationsDoNotOpen() throws {
        for source in [
            "cite:host_0123456789abcdef0123456789abcdef", "CiTe:missing",
            "cite:", "cite://untrusted.example/path?data=opaque#fragment",
            "cite:invalid%20field", "scholium-zotero:1:AAAA", "SCHOLIUM-ZOTERO:unsupported",
        ] {
            let url = try #require(URL(string: source))
            var dispatched: [URL] = []
            let opened = WorkspaceStore.openExternal(url) {
                dispatched.append($0)
                return true
            }
            #expect(!opened)
            #expect(dispatched.isEmpty)
        }
    }

    @Test("Zotero navigation retains validated item, PDF, page and annotation destinations")
    func zoteroNavigationRetainsExactReference() throws {
        for source in [
            "zotero://select/library/items/ITEM0001",
            "zotero://select/groups/42/items/ITEM0001",
            "zotero://open-pdf/library/items/PDF00001",
            "zotero://open-pdf/groups/42/items/PDF00001?page=3&annotation=ANN00001",
            "zotero://open-pdf/library/items/PDF00001?annotation=ANN00001",
        ] {
            let url = try #require(URL(string: source))
            var dispatched: [URL] = []
            #expect(
                WorkspaceStore.openExternal(url) {
                    dispatched.append($0)
                    return true
                })
            #expect(dispatched == [try ZoteroReference(url: url).url])
        }
    }

    @Test("Invalid Zotero links cannot bypass the shared native opening boundary")
    func invalidZoteroReferencesDoNotOpen() throws {
        for source in [
            "zotero://debug/", "zotero://select/library/items/ITEM0001?page=2",
            "zotero://open-pdf/library/items/PDF00001?page=0",
            "zotero://open-pdf/library/items/PDF00001?annotation=A&annotation=B",
        ] {
            let url = try #require(URL(string: source))
            var opened = false
            #expect(
                !WorkspaceStore.openExternal(url) { _ in
                    opened = true
                    return true
                })
            #expect(!opened)
        }
    }

    @Test("Ordinary authored destinations and opener results remain unchanged")
    func ordinaryExternalNavigationRemainsIndependent() throws {
        for source in [
            "https://doi.org/10.1234/example", "https://example.org/?next=cite:missing",
            "mailto:reader@example.org", "obsidian://open?vault=Example&file=Note",
        ] {
            let url = try #require(URL(string: source))
            var dispatched: [URL] = []
            #expect(
                !WorkspaceStore.openExternal(url) {
                    dispatched.append($0)
                    return false
                })
            #expect(dispatched == [url])
        }
    }
}
