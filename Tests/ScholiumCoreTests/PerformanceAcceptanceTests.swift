import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Performance regression microbenchmarks")
struct PerformanceRegressionMicrobenchmarkTests {
    @Test("A generated long-note semantic projection remains under one second")
    func coldReadProjection() {
        let paragraph = "A philosophical argument distinguishes evidence, inference, objection, reply, source, authority, and conclusion with explicit uncertainty. "
        let body = (0..<500).map { index in
            index.isMultiple(of: 25)
                ? "\n## Section \(index / 25 + 1)\n\n> [!argument] Step \(index)\n> \(paragraph)\n\nClaim[^n\(index)].\n\n[^n\(index)]: \(paragraph)"
                : paragraph
        }.joined(separator: " ")
        let document = NoteDocument(relativePath: "Long.md", rawContent: body)
        let elapsed = measured { _ = SafeMarkdownRenderer.render(document) }
        #expect(elapsed < 1.0, "Cold Read projection took \(elapsed) seconds")
    }

    @Test("Internal SQLite search over 800 generated notes remains under 100 milliseconds at p95")
    func indexedSearchP95() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vaultID = UUID()
        let index = try SQLiteSearchIndex(databaseURL: root.appendingPathComponent("search.sqlite"), vaultID: vaultID)
        let documents = (0..<800).map { number in
            let content = """
            ---
            title: Philosophical Note \(number)
            authors: [Researcher \(number % 17)]
            year: \(1950 + number % 77)
            tags: [normativity, cluster-\(number % 9)]
            ---
            # Argument \(number)
            Deliberative control and normative reasons appear in note \(number). 哲学概念需要精确分析。
            """
            return SearchIndexDocument(
                vaultID: vaultID,
                vaultName: "Performance Fixture",
                vaultRole: .sourceCorpus,
                document: NoteDocument(relativePath: "Papers/Note-\(number).md", rawContent: content)
            )
        }
        _ = try await index.rebuild(documents)
        _ = try await index.search(SearchQuery("deliberative tag:normativity"), limit: 50)

        var samples: [Double] = []
        for iteration in 0..<40 {
            let started = ContinuousClock.now
            _ = try await index.search(
                SearchQuery(iteration.isMultiple(of: 2) ? "deliberative cluster-3" : "哲学 author:Researcher"),
                limit: 50
            )
            samples.append(seconds(started.duration(to: .now)))
        }
        samples.sort()
        let p95 = samples[min(samples.count - 1, Int(Double(samples.count) * 0.95))]
        #expect(p95 < 0.100, "Internal 800-note SQLite search p95 was \(p95) seconds")
    }

    private func measured(_ operation: () -> Void) -> Double {
        let started = ContinuousClock.now
        operation()
        return seconds(started.duration(to: .now))
    }

    private func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
