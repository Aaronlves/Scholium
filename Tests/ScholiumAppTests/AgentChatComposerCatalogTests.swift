import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Composer command, material and Skill catalogs") @MainActor
struct AgentChatComposerCatalogTests {
    @Test("Slash commands use readable tokens and gate only the relevant actions")
    func commands() {
        let idle = AgentChatComposerCatalog.commands(isBusy: false, hasChanges: true, hasAgents: true)
        #expect(idle.map(\.id) == ["context", "usage", "find", "outline", "changes", "agents", "skills", "web-default", "web-off", "web-cached", "web-live"])
        for candidate in idle {
            #expect(candidate.title == "/" + candidate.id)
            let hasWhitespace = candidate.id.contains { $0.isWhitespace }
            #expect(!hasWhitespace)
            #expect(!candidate.detail.isEmpty)
        }
        let busy = AgentChatComposerCatalog.commands(isBusy: true, hasChanges: false, hasAgents: false)
        #expect(busy.map(\.id) == ["context", "usage", "find", "outline", "skills"])
        #expect(AgentChatComposerCatalog.commands(isBusy: true, hasChanges: true, hasAgents: true).count == 7)
        let modes = idle.compactMap { candidate -> AgentChatPreferences.WebSearch? in
            guard case .webSearch(let mode) = candidate.action else { return nil }
            return mode
        }
        #expect(modes == [.runtimeDefault, .disabled, .cached, .live])
    }

    @Test("Material candidates keep every valid Note and all three material routes")
    func materials() {
        let notes =
            (1...9).reversed().map { note("Note \($0)", stableID: UUID().uuidString) }
            + [note("Unresolved", stableID: nil), note("Invalid", stableID: "not-a-uuid")]
        let candidates = AgentChatComposerCatalog.materials(notes: notes)
        #expect(candidates.count == 12)
        #expect(Array(candidates.prefix(9)).map(\.title) == (1...9).map { "Note \($0)" })
        #expect(candidates.allSatisfy { $0.id.hasPrefix("material:") })
        #expect(Set(candidates.map(\.id)).count == candidates.count)
        #expect(candidates.suffix(3).map(\.id) == ["material:file", "material:note-picker", "material:selection"])
        #expect(AgentChatComposerCatalog.matching(candidates, query: "Note").count >= 9)
    }

    @Test("Skill candidates exclude protected and disabled entries without truncation")
    func skills() {
        let methods =
            (1...8).map { method("method-\($0)") }
            + [method("scholium-core-protocol"), method("disabled", enabled: false)]
        let candidates = AgentChatComposerCatalog.skills(methods: methods, canRefresh: true)
        let selections = candidates.compactMap { candidate -> AgentChatMethodSelection? in
            guard case .method(let selection) = candidate.action else { return nil }
            return selection
        }
        #expect(selections.map(\.name) == (1...8).map { "method-\($0)" })
        #expect(candidates.count == 10)
        #expect(candidates.suffix(2).map(\.id) == ["skill-action:refresh", "skill-action:manage"])
        let unavailable = AgentChatComposerCatalog.skills(methods: methods, canRefresh: false)
        #expect(!unavailable.contains { $0.id == "skill-action:refresh" })
        #expect(unavailable.last?.id == "skill-action:manage")
    }

    @Test("Matching promotes exact then prefix matches and preserves ties and the complete list")
    func ranking() {
        let candidates: [AgentChatComposerCandidate] = [
            candidate("contains", "A context action"),
            candidate("prefix-first", "Context details"),
            candidate("context", "/context"),
            candidate("prefix-second", "Context usage"),
            candidate("detail", "Other", detail: "Prior context"),
            candidate("unmatched", "Other"),
        ]
        #expect(
            AgentChatComposerCatalog.matching(candidates, query: " CONTEXT ").map(\.id)
                == ["context", "prefix-first", "prefix-second", "contains", "detail"])
        let many = (1...12).map { candidate("item-\($0)", "Match \($0)") }
        #expect(AgentChatComposerCatalog.matching(many, query: "match").map(\.id) == many.map(\.id))
        #expect(AgentChatComposerCatalog.matching(many, query: "  ").map(\.id) == many.map(\.id))
        #expect(AgentChatComposerCatalog.matching(many, query: "absent").isEmpty)
    }

    private func candidate(_ id: String, _ title: String, detail: String = "") -> AgentChatComposerCandidate {
        .init(id: id, title: title, detail: detail, symbol: "doc.text", action: .file)
    }

    private func method(_ name: String, enabled: Bool = true) -> AgentChatMethod {
        .init(
            selection: .init(name: name, title: name, path: "/fixture/skills/\(name)/SKILL.md"),
            description: "Supplied Skill description", enabled: enabled, scope: "fixture")
    }

    private func note(_ title: String, stableID: String?) -> WorkspaceCatalogNote {
        .init(
            reference: .init(
                vaultID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                vaultName: "Topics", vaultRole: .topicKnowledge, relativePath: "\(title).md", stableNoteID: stableID),
            title: title, fingerprint: DocumentFingerprint(content: "# \(title)\n"), validationWarnings: [])
    }
}
