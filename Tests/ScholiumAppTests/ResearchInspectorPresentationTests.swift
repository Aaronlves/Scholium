import AppKit
import ScholiumContracts
import SwiftUI
import Synchronization
import Testing

@testable import ScholiumApp

/// Hosted component geometry, not live Inspector interaction or motion evidence.
@Suite("Research Inspector presentation", .serialized)
@MainActor
struct ResearchInspectorPresentationTests {
    @Test("Initial placeholders retain real header and excerpt geometry", arguments: [220.0, 320.0])
    func skeletonGeometry(width: CGFloat) async throws {
        for separated in [false, true] {
            let actual = try await rowSizes(width: width) {
                ResearchNoteGroupHeader(
                    title: ScholiumL10n.dynamicString("Writing References"), role: nil,
                    expanded: .constant(true), separatesFromPreviousGroup: separated
                ) {
                    Button("Open Linked Note", action: {})
                }
                VStack(alignment: .leading, spacing: 0) {
                    passage(Array(repeating: ScholiumL10n.dynamicString("Writing References"), count: 10).joined(separator: " "))
                    ResearchPassageContextDisclosure(expanded: .constant(false), identity: "", identifier: "test")
                        .padding(.leading, ScholiumGrid.Apparatus.passageLeadingInset)
                }
            }
            let placeholder = try await rowSizes(width: width) {
                RelatedMaterialSkeleton(separatesFromPreviousGroup: separated)
            }
            try #require(actual.count == 2 && placeholder.count == 2)
            expectSameGeometry(actual, placeholder)
        }
    }

    @Test("Compact excerpts stop at three lines; deliberate expansion retains complete text")
    func excerptNaturalSize() async throws {
        let short = try await rowSizes(width: 220) { passage("A brief passage.") }
        let medium = "A research note preserves the distinction between a source claim and an interpretation. 原文与解释需要区分。"
        let narrow = try await rowSizes(width: 220) { passage(medium) }
        let ordinary = try await rowSizes(width: 320) { passage(medium) }
        let threeLines = try await rowSizes(width: 220) { passage("One\nTwo\nThree") }
        let fiveLines = try await rowSizes(width: 220) { passage("One\nTwo\nThree\nFour\nFive") }
        let tenLines = try await rowSizes(width: 220) { passage("One\nTwo\nThree\nFour\nFive\nSix\nSeven\nEight\nNine\nTen") }
        let expanded = try await rowSizes(width: 220) {
            ResearchPassageLayout {
                ResearchPassageExcerpt(text: Text("One\nTwo\nThree\nFour\nFive\nSix\nSeven\nEight\nNine\nTen"), isExpanded: true)
            }
        }
        let shortSize = try #require(short.first)
        let narrowSize = try #require(narrow.first)
        let ordinarySize = try #require(ordinary.first)
        let threeSize = try #require(threeLines.first)
        let fiveSize = try #require(fiveLines.first)
        let tenSize = try #require(tenLines.first)
        #expect(shortSize.height < ordinarySize.height)
        #expect(ordinarySize.height <= narrowSize.height)
        #expect(abs(threeSize.height - fiveSize.height) < 0.5)
        #expect(abs(fiveSize.height - tenSize.height) < 0.5)
        #expect(try #require(expanded.first).height > tenSize.height * 2)
        #expect(narrowSize.width <= 220 && ordinarySize.width <= 320)
    }

    @Test("Retained real groups keep row geometry when redacted", arguments: [220.0, 320.0])
    func retainedGroupGeometry(width: CGFloat) async throws {
        let group = fixtureGroup()
        let ready = try await rowSizes(width: width) { result(group, loading: false) }
        let loading = try await rowSizes(width: width) {
            result(group, loading: true)
        }
        try #require(ready.count == 3 && loading.count == ready.count)
        expectSameGeometry(ready, loading)
    }

    @Test("Measured compact context retains late Chinese matches at narrow and enlarged sizes", arguments: [13.0, 20.0])
    func matchFitsVisibleLines(pointSize: CGFloat) async throws {
        let text = String(repeating: "这是需要保留的限定语，", count: 16) + "不是目标概念的证明，" + String(repeating: "仍需检查上下文，", count: 16)
        let match = NSRange(try #require(text.range(of: "目标概念")), in: text)
        for width in [160.0, 260.0] {
            let preview = ResearchPassagePreview.fittingExcerpt(
                source: text, matches: [match.location..<NSMaxRange(match)], width: width, pointSize: pointSize)
            #expect(preview.text.contains("不是目标概念"))
            let complete = try await rowSizes(width: width) {
                ResearchPassageExcerpt(text: Text(verbatim: preview.text), isExpanded: true)
                    .font(.system(size: pointSize)).lineSpacing(ScholiumGrid.Apparatus.passageLineSpacing)
            }
            let compact = try await rowSizes(width: width) {
                ResearchPassageExcerpt(text: Text(verbatim: preview.text))
                    .font(.system(size: pointSize)).lineSpacing(ScholiumGrid.Apparatus.passageLineSpacing)
            }
            expectSameGeometry(complete, compact)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_RESEARCH_INSPECTOR"] == "1"))
    func renderResearchRows() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let output = repository.appendingPathComponent(".build/research-inspector-refinement/renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        // These are real row components in the real native List style, not a
        // facsimile of the entire window or a claim about dynamic retrieval.
        for (name, width, scheme) in [
            ("narrow-light", 260.0, ColorScheme.light),
            ("ordinary-dark-contrast", 340.0, .dark),
        ] {
            for state in ["results", "initial-loading", "retained-loading"] {
                let loading = state == "retained-loading"
                let content = List {
                    Group {
                        if state == "initial-loading" {
                            RelatedMaterialSkeleton()
                            RelatedMaterialSkeleton(separatesFromPreviousGroup: true)
                        } else {
                            result(fixtureGroup(), loading: loading)
                            Group {
                                ResearchNoteGroupHeader(
                                    title: "Related source — 研究材料", role: .sourceCorpus,
                                    expanded: .constant(true), separatesFromPreviousGroup: true
                                ) {
                                    Button("Open Linked Note", action: {})
                                }
                                passage("A shorter source passage leaves the rest of the page quiet.")
                            }
                            .redacted(reason: loading ? .placeholder : [])
                            .modifier(ResearchSkeletonPulse(isActive: loading))
                            .disabled(loading)
                            .allowsHitTesting(!loading)
                        }
                    }.researchListRow()
                }
                .researchListStyle()
                .frame(width: width, height: 640)
                .background(ScholiumColorRole.documentBackground.color)
                .environment(\.colorScheme, scheme)
                // Static capture only; this does not simulate Reduce Motion.
                .transaction {
                    $0.animation = nil
                    $0.disablesAnimations = true
                }
                let host = NSHostingView(rootView: AnyView(content))
                host.appearance = NSAppearance(named: scheme == .light ? .aqua : .accessibilityHighContrastDarkAqua)
                await layout(host)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = host.appearance
                window.contentView = host
                defer {
                    window.contentView = nil
                    window.close()
                }
                await layout(host)
                host.displayIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: output.appendingPathComponent("\(name)-\(state).png"))
            }
        }
    }

    private func passage(_ text: String) -> some View {
        ResearchPassageLayout { ResearchPassageExcerpt(text: Text(verbatim: text)) }
    }

    private func result(_ group: RelatedMaterialsSession.NoteGroup, loading: Bool) -> some View {
        RelatedMaterialNoteGroupView(
            group: group, keptPassages: KeptPassagesSession(), canInsert: false, canInsertParagraph: false, canAddToChat: !loading,
            isLoading: loading, entranceProgress: 1,
            open: { _ in }, insert: { _ in }, insertParagraph: { _ in }, addToChat: { _ in }, keepRelated: { _ in }
        )
        .redacted(reason: loading ? .placeholder : [])
        .modifier(ResearchSkeletonPulse(isActive: loading))
        .disabled(loading)
        .allowsHitTesting(!loading)
    }

    private func fixtureGroup() -> RelatedMaterialsSession.NoteGroup {
        let vault = UUID()
        let reference = VaultNoteReference(
            vaultID: vault, vaultName: "Fixture Topics", vaultRole: .topicKnowledge,
            relativePath: "研究/Freedom.md")
        let excerpts = [
            "The question concerns freedom and the conditions under which an action can be attributed to its author. 这段合成文字只用于检查自然换行，并不作为哲学论断。",
            "A shorter passage. 一段较短的材料。",
        ]
        let candidate = RelatedContentCandidate(
            note: .init(vaultID: vault, relativePath: reference.relativePath), vaultRole: .topicKnowledge,
            title: "Freedom and practical judgment — 自由与实践判断", fingerprint: .init(content: excerpts.joined(separator: "\n\n")),
            reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [.init(seedKind: .selectedPassage, terms: ["freedom"])])))
        var offset = 0
        let cards = excerpts.enumerated().map { index, text in
            defer { offset += text.utf16.count + 2 }
            let passage = RelatedContentPassage(
                candidate: candidate,
                range: .init(
                    utf16LowerBound: offset, utf16UpperBound: offset + text.utf16.count,
                    line: index * 2 + 1, column: 1, endLine: index * 2 + 1, endColumn: text.utf16.count + 1),
                source: text, displayText: text, excerpt: text, excerptMatches: [],
                matches: [.init(seedKind: .selectedPassage, terms: ["freedom"])])
            return RelatedMaterialCard(passage: passage, reference: reference)
        }
        return .init(id: candidate.note, passages: cards, directoryContext: "Fixture Topics / 研究")
    }

    private func rowSizes<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) async throws -> [CGSize] {
        let measurement = RowMeasurement()
        let host = makeHost(width: width) { MeasuredRows(measurement: measurement) { content() } }
        await layout(host)
        let sizes = measurement.sizes.withLock { $0 }
        try #require(!sizes.isEmpty)
        #expect(sizes.allSatisfy { $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0 })
        return sizes
    }

    private func makeHost<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> NSHostingView<AnyView> {
        NSHostingView(
            rootView: AnyView(
                content().frame(width: width).transaction {
                    $0.animation = nil
                    $0.disablesAnimations = true
                }))
    }

    private func layout(_ host: NSHostingView<AnyView>) async {
        for _ in 0..<5 {
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
    }

    private func expectSameGeometry(_ first: [CGSize], _ second: [CGSize]) {
        for (index, pair) in zip(first, second).enumerated() {
            #expect(abs(pair.0.width - pair.1.width) < 0.5, "Row \(index) width changed")
            #expect(abs(pair.0.height - pair.1.height) < 0.5, "Row \(index): \(pair.0.height) became \(pair.1.height)")
        }
    }

}

/// Observe the natural size of each real List row without depending on private
/// SwiftUI/AppKit subview class names or introducing production measurement hooks.
private final class RowMeasurement: Sendable {
    let sizes = Mutex<[CGSize]>([])
}

private struct MeasuredRows: Layout {
    let measurement: RowMeasurement

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.init(width: proposal.width, height: nil)) }
        return .init(width: sizes.map(\.width).max() ?? 0, height: sizes.reduce(0) { $0 + $1.height })
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let childProposal = ProposedViewSize(width: bounds.width, height: nil)
        let sizes = subviews.map { $0.sizeThatFits(childProposal) }
        measurement.sizes.withLock { $0 = sizes }
        var y = bounds.minY
        for (subview, size) in zip(subviews, sizes) {
            subview.place(at: .init(x: bounds.minX, y: y), anchor: .topLeading, proposal: childProposal)
            y += size.height
        }
    }
}
