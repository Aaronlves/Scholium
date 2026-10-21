import AppKit
import Foundation
import Testing

@testable import ScholiumApp

@Suite("Native floating choice sizing", .serialized)
@MainActor
struct NativeFloatingChoiceSizingTests {
    private func makeList() -> NativeFloatingChoiceList {
        _ = NSApplication.shared
        let list = NativeFloatingChoiceList(acceptsKeyboard: false)
        list.frame = NSRect(x: 0, y: 0, width: 368, height: 280)
        return list
    }

    private var syntheticItems: [NativeFloatingChoiceList.Item] {
        (0..<100).map { index in
            .init(
                label: "Synthetic candidate \(index) · 混合语言笔记标题",
                detail: "Synthetic folder / Group \(index % 8) · 说明文字用于尺寸测量")
        }
    }

    @Test("Selection and availability keep measured text width while content and appearance invalidate it")
    func contentOwnsWidthMeasurement() {
        let list = makeList()
        var items = syntheticItems
        list.update(items: items, selected: 0)
        list.layoutSubtreeIfNeeded()
        let original = list.preferredSize
        let measured = list.measuredWidthItemCount
        for selected in 0..<items.count {
            list.update(items: items, selected: selected)
            #expect(list.preferredSize == original)
        }
        #expect(list.measuredWidthItemCount == measured)
        items[0].disabled = true
        items[0].accessibilityValue = "Unavailable synthetic choice"
        list.update(items: items, selected: 1)
        #expect(list.preferredSize == original)
        #expect(list.measuredWidthItemCount == measured)

        items[0] = .init(label: "Short", detail: "New detail", indentation: 5)
        list.update(items: items, selected: 1)
        _ = list.preferredSize
        #expect(list.measuredWidthItemCount == measured + items.count)
        let afterContent = list.measuredWidthItemCount
        list.viewDidChangeEffectiveAppearance()
        _ = list.preferredSize
        #expect(list.measuredWidthItemCount == afterContent + items.count)
    }

    @Test("Filtering, empty content, and native row heights retain bounded dimensions")
    func filterAndRowGeometry() {
        let list = makeList()
        list.update(items: [.init(label: "Date")], selected: 0)
        list.layoutSubtreeIfNeeded()
        let short = list.preferredSize
        #expect(short.width > 0 && short.width < 100 && short.height > 0)
        list.update(items: [.init(label: "A longer choice", detail: "说明文字")], selected: 0)
        list.layoutSubtreeIfNeeded()
        let detailed = list.preferredSize
        #expect(detailed.width > short.width && detailed.height > short.height)
        list.update(items: [.init(label: String(repeating: "研究笔记", count: 40))], selected: 0)
        #expect(list.preferredSize.width == 368)
        list.update(items: [.init(label: "Date")], selected: 0)
        #expect(list.preferredSize == short)
        list.update(items: [])
        #expect(list.preferredSize == .zero)
    }

    @Test(
        "Diagnostic: repeated preferred size with 100 unchanged choices",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_FLOATING_CHOICES"] == "1"))
    func repeatedPreferredSizeDiagnostic() throws {
        let list = makeList()
        list.update(items: syntheticItems, selected: 0)
        list.layoutSubtreeIfNeeded()
        _ = list.preferredSize
        let measured = list.measuredWidthItemCount
        let pairsPerRound = 100
        var checksum = 0.0
        var rounds: [Double] = []
        for _ in 0..<3 {
            let start = ContinuousClock.now
            for _ in 0..<pairsPerRound {
                let first = list.preferredSize
                let second = list.preferredSize
                checksum += first.width + second.height
            }
            let duration = start.duration(to: .now)
            rounds.append(Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
        }
        #expect(checksum.isFinite && checksum > 0)
        #expect(list.measuredWidthItemCount == measured)
        let result: [String: Any] = [
            "items": list.items.count,
            "preferred_size_calls_per_pair": 2,
            "pairs_per_round": pairsPerRound,
            "rounds_ms": rounds,
            "ms_per_pair": rounds.map { $0 / Double(pairsPerRound) },
            "checksum": checksum,
            "additional_text_measurements": list.measuredWidthItemCount - measured,
            "boundary": "Warm synchronous preferredSize only; excludes item update, bridge, layout invalidation, rendering, and event delivery.",
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("FLOATING_PROBE choice-sizing \(String(decoding: data, as: UTF8.self))")
    }
}
