import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("File operation presentation", .serialized)
@MainActor
struct FileOperationPresentationTests {
    @Test("File sheets fit short content, retain long paths, and bound large batches")
    func fittedNativeSheets() async throws {
        _ = NSApplication.shared
        let vault = UUID()
        let paths = ["议题/Reasons and objections.md", "研究/一个较长的哲学论证笔记标题.md", "Drafts/Working notes.md"]
        let targets = paths.map {
            NoteMutationTarget(documentID: .init(vaultID: vault, relativePath: $0), stableNoteID: UUID(), revision: .init(content: "Fixture"))
        }
        func batch(_ count: Int, outcome: LibraryNoteBatchOutcome? = nil, working: Bool = false, folders: [String] = ["", "Research"]) -> AnyView {
            let request =
                outcome?.request
                ?? LibraryNoteBatchRequest(
                    assignmentID: UUID(), vaultID: vault,
                    targets: count == 3
                        ? targets
                        : (0..<count).map {
                            .init(
                                documentID: .init(vaultID: vault, relativePath: "研究/长路径与论证/Note \($0).md"), stableNoteID: UUID(),
                                revision: .init(content: "Fixture"))
                        })
            return AnyView(
                LibraryNoteBatchView(
                    request: request, folderRelativePaths: folders, outcome: outcome, isWorking: working,
                    move: { _ in Issue.record("Rendering must not move files") }, cancel: {}, retry: {}, close: {}, openRecovery: {}))
        }
        let request = LibraryNoteBatchRequest(assignmentID: UUID(), vaultID: vault, targets: targets)
        let outcome = LibraryNoteBatchOutcome(
            request: request, operation: .move(folderRelativePath: "Research"),
            items: [
                .init(target: targets[0], destinationRelativePath: "Research/Reasons and objections.md", status: .succeeded),
                .init(
                    target: targets[1], destinationRelativePath: nil, status: .failed("A note with this filename already exists. Choose another destination.")),
                .init(target: targets[2], destinationRelativePath: nil, status: .unattempted),
            ], recoveryRequired: false, warnings: [])
        let recovery = LibraryNoteBatchOutcome(
            request: request, operation: .systemTrash,
            items: targets.map {
                .init(target: $0, destinationRelativePath: nil, status: .outcomeUnknown("Review the retained recovery plan before continuing."))
            },
            recoveryRequired: true, warnings: [])
        let noteActions = NoteFileActions(duplicate: { _, _ in Issue.record("Unexpected duplicate") }, move: { _, _ in Issue.record("Unexpected move") })
        let folder = FolderMutationTarget(vaultID: vault, relativePath: "Research/论证与异议")
        let preview = SystemTrashDeletionPreview(
            triptychID: UUID(),
            sources: targets.map {
                .init(
                    vaultID: vault, relativePath: $0.relativePath, kind: .note,
                    notes: [.init(noteID: $0.stableNoteID, relativePath: $0.relativePath, expectedRevision: $0.revision)])
            })
        let examples: [(String, AnyView)] = [
            ("rename", AnyView(NoteFileOperationView(request: .rename(targets[0]), actions: noteActions))),
            ("move", AnyView(NoteFileOperationView(request: .move(targets[0]), actions: noteActions))),
            ("duplicate", AnyView(NoteFileOperationView(request: .duplicate(targets[0]), actions: noteActions))),
            (
                "folder",
                AnyView(
                    FolderFileOperationView(
                        request: .move(folder), folderRelativePaths: ["Research", "Drafts"], actions: .init(move: { _, _ in Issue.record("Unexpected move") })))
            ),
            ("batch", batch(3)), ("large-batch", batch(40)), ("working", batch(3, working: true)), ("partial", batch(3, outcome: outcome)),
            ("unavailable", batch(3, folders: [])), ("recovery", batch(3, outcome: recovery)),
            ("trash", AnyView(SystemTrashConfirmationView(preview: preview, confirm: { _ in Issue.record("Unexpected Trash") }, cancel: {}))),
        ]
        for (name, content) in examples {
            for narrow in [false, true] {
                let width: CGFloat = narrow ? 320 : 520
                let host = NSHostingView(
                    rootView:
                        content
                        .environment(\.locale, Locale(identifier: narrow ? "zh-Hans" : "en"))
                        .environment(\.colorScheme, narrow ? .dark : .light)
                        .frame(width: width))
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer {
                    window.contentView = nil
                    window.close()
                }
                host.appearance = NSAppearance(named: narrow ? .accessibilityHighContrastDarkAqua : .aqua)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                window.setContentSize(NSSize(width: width, height: host.fittingSize.height))
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(80))
                window.setContentSize(NSSize(width: width, height: host.fittingSize.height))
                host.layoutSubtreeIfNeeded()
                #expect(abs(host.bounds.width - width) < 0.5)
                #expect(host.bounds.height > 120 && host.bounds.height < 700)
                if !narrow && ["rename", "move", "duplicate", "folder"].contains(name) {
                    #expect(host.bounds.height < 320)
                }
                for button in descendants(host).compactMap({ $0 as? NSButton }) where !button.isHiddenOrHasHiddenAncestor {
                    let frame = button.convert(button.bounds, to: host)
                    #expect(frame.minX >= -1 && frame.maxX <= width + 1)
                    #expect(frame.minY >= -1 && frame.maxY <= host.bounds.height + 1)
                }
                let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().appendingPathComponent(".build/file-operation-review")
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: output.appendingPathComponent("\(name)-\(narrow ? "narrow-dark" : "light").png"))
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
