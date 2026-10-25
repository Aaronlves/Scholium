import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite(
    "Related card link preparation diagnostic", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_RELATED_LINK_TARGETS"] == "1"))
@MainActor
struct RelatedMaterialLinkPreparationPerformanceTests {
    private struct Row {
        let reference: VaultNoteReference
        let title: String
        let aliases: [String]
        var note: LinkCatalogNote {
            .init(id: .init(vaultID: reference.vaultID, relativePath: reference.relativePath), title: title, aliases: aliases)
        }
    }

    @Test("Attribute bounded card targets over a realistic catalog", arguments: [500, 5_000])
    func cardTargets(count: Int) throws {
        let vaults = (1...3).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", $0))! }
        let roles: [VaultRole] = [.sourceCorpus, .topicKnowledge, .draftProject]
        let rows = (0..<count).map { index in
            Row(
                reference: .init(
                    vaultID: vaults[index % 3], vaultName: ["Analyses", "Topics", "Works"][index % 3],
                    vaultRole: roles[index % 3], relativePath: "Section\(index / 20)/Note\(index % 20).md",
                    stableNoteID: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012x", index + 1))!.uuidString),
                title: "Freedom and autonomy 自由 \(index)", aliases: ["Agency \(index % 7)", "自主 \(index)"])
        }
        let catalog = rows.map {
            WorkspaceCatalogNote(
                reference: $0.reference, title: $0.title, aliases: $0.aliases,
                fingerprint: .init(content: $0.title), validationWarnings: [])
        }
        let origin = VaultQualifiedNoteID(vaultID: vaults[2], relativePath: "Draft.md")
        let six = [count - 1, count - 1, count / 2, count / 2, count / 3, count / 4].map { rows[$0].reference }
        var reports: [[String: Any]] = []
        for (label, references) in [("empty", [VaultNoteReference]()), ("one", Array(six.prefix(1))), ("six", six)] {
            func current() -> [String?] {
                references.map { reference in
                    guard rows.contains(where: { $0.reference == reference }) else { return nil }
                    let resolver = LinkResolutionCatalog(catalog: rows.map(\.note))
                    guard
                        case .available(let target) = resolver.wikilinkTarget(
                            for: .init(vaultID: reference.vaultID, relativePath: reference.relativePath), from: origin)
                    else { return nil }
                    return target
                }
            }
            func oneResolver() -> [String?] {
                let targets = RelatedMaterialLinkPreparation.targets(for: references, catalog: catalog, from: origin)
                return references.map { targets[$0] }
            }

            var baseline: [Double] = []
            var proposed: [Double] = []
            let expected = current()
            func measure(_ body: () -> [String?]) -> ([String?], Double) {
                let start = ContinuousClock.now
                let value = body()
                let duration = start.duration(to: .now).components
                return (value, Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
            }
            for iteration in 0..<12 {
                try autoreleasepool {
                    let before: ([String?], Double)
                    let after: ([String?], Double)
                    if iteration.isMultiple(of: 2) {
                        before = measure(current)
                        after = measure(oneResolver)
                    } else {
                        after = measure(oneResolver)
                        before = measure(current)
                    }
                    try #require(before.0 == expected && after.0 == expected)
                    if iteration >= 2 {
                        baseline.append(before.1)
                        proposed.append(after.1)
                    }
                }
            }
            reports.append([
                "catalog_notes": count, "cards": references.count, "shape": label,
                "baseline_ms": baseline, "production_batch_ms": proposed,
                "targets": expected.map { $0 as Any? ?? NSNull() },
            ])
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/related-link-preparation")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let report: [String: Any] = [
            "configuration": "Debug phase-only diagnostic; not native or retrieval latency",
            "warmups": 2, "samples": 10, "reports": reports,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("\(count)-production.json"), options: .atomic)
        print("Related link preparation diagnostic: \(root.path)/\(count)-production.json")
    }
}
