import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

/// Opt-in diagnosis of the Library's Folder presentation work. These synthetic
/// distributions exclude source enumeration, tree construction and rendering.
@Suite("Library Folder presentation measurement", .serialized)
@MainActor
struct LibraryFolderPerformanceTests {
    @Test(
        "Unchanged Folder inventory mapping and localized ordering",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_LIBRARY_FOLDERS_MEASURE"] == "1"),
        arguments: [2_000, 10_000]
    )
    func folderPresentation(folderCount: Int) throws {
        // 7,919 is coprime to both sizes, giving each numeric path exactly once
        // in a fixed unsorted order. The oracle follows integer order directly.
        let folders = try (0..<folderCount).map { index in
            try VaultRelativeFolderPath("Folder-\((index * 7_919) % folderCount)")
        }
        let expected = (0..<folderCount).map { "Folder-\($0)" }
        let check: ([String]) -> Void = { result in
            #expect(result.count == expected.count)
            #expect(zip(result, expected).allSatisfy { $0.utf8.elementsEqual($1.utf8) })
        }
        measure("map-sort", folderCount: folderCount) {
            folders.map(\.rawValue).sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
        } check: {
            check($0)
        }
        measure("cache-cold", folderCount: folderCount) {
            LibraryPresentationCache().orderedFolders(folders)
        } check: {
            check($0)
        }
        let cache = LibraryPresentationCache()
        check(cache.orderedFolders(folders))
        measure("cache-warm-same-input", folderCount: folderCount) {
            cache.orderedFolders(folders)
        } check: {
            check($0)
        }
    }

    private func measure(
        _ stage: String, folderCount: Int, operation: () -> [String], check: ([String]) -> Void
    ) {
        let samples = 31
        for _ in 0..<3 { check(operation()) }
        var milliseconds: [Double] = []
        for _ in 0..<samples {
            let start = ContinuousClock.now
            let result = operation()
            let duration = start.duration(to: .now)
            milliseconds.append(
                Double(duration.components.seconds) * 1_000
                    + Double(duration.components.attoseconds) / 1e15)
            check(result)
        }
        let sorted = milliseconds.sorted()
        let format: (Double) -> String = { String(format: "%.4f", $0) }
        print(
            "LIBRARY_FOLDERS_MEASURE stage=\(stage) folders=\(folderCount) warmups=3 samples=\(samples)"
                + " median_ms=\(format(sorted[samples / 2]))"
                + " p95_ms=\(format(sorted[Int(ceil(Double(samples) * 0.95)) - 1]))"
                + " min_ms=\(format(sorted.first!)) max_ms=\(format(sorted.last!))")
    }
}
