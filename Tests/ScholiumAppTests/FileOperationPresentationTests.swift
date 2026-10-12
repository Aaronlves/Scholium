import AppKit
import Observation
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("File operation presentation", .serialized)
@MainActor
struct FileOperationPresentationTests {
    @Test("A presented file sheet retains its content and action insets")
    func presentedSheetInsets() async throws {
        _ = NSApplication.shared
        let markers = SheetInsetMarkers()
        let state = SheetFixtureState()
        let host = NSHostingView(
            rootView: Color.clear.sheet(isPresented: .constant(true)) {
                FileOperationSheet(title: Text("Import to Triptych…"), message: Text("Import a copy of the current content. The original file stays in place."))
                {
                    Text("QA External Markdown.md").background(SheetInsetMarker(name: "filename", markers: markers))
                    if state.isLoading {
                        ProgressView("Loading Triptychs…")
                    } else {
                        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
                            Picker("Triptych", selection: .constant(0)) { Text("Test Triptych").tag(0) }.pickerStyle(.menu)
                            Picker("Workspace", selection: .constant(0)) { Text("Topics").tag(0) }.pickerStyle(.menu)
                            Text("/Synthetic/Research/Long paths in a selected Triptych/Library/研究笔记/一个较长的研究库路径/02-topics")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } actions: {
                    Button("Cancel") {}.background(SheetInsetMarker(name: "cancel", markers: markers))
                    Spacer()
                    Button("Import") {}.keyboardShortcut(.defaultAction).background(SheetInsetMarker(name: "import", markers: markers))
                }
            })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
                sheet.close()
            }
            window.contentView = nil
            window.close()
        }
        for _ in 0..<50 where window.attachedSheet == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        let sheet = try #require(window.attachedSheet)
        let content = try #require(sheet.contentView)
        state.isLoading = false
        try await Task.sleep(for: .milliseconds(500))
        try await Task.sleep(for: .milliseconds(100))
        content.layoutSubtreeIfNeeded()
        #expect(markers.views.count == 3)
        let inset = ScholiumMetrics.ResearchSheet.contentInset
        for (name, view) in markers.views {
            let frame = view.convert(view.bounds, to: content)
            print("Sheet inset marker \(name): \(frame), content \(content.bounds)")
            #expect(frame.minX >= inset - 1)
            #expect(frame.maxX <= content.bounds.width - inset + 1)
            #expect(frame.minY >= inset - 1)
            #expect(frame.maxY <= content.bounds.height - inset + 1)
        }
    }

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
                if !narrow && ["move", "duplicate", "folder"].contains(name) {
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

    @Test(
        "Failed file operations keep the reason beside editable drafts and allow retry",
        .enabled(if: ScholiumTestEnvironment.providesDisplayEvidence), arguments: FileOperationFailureFixture.allCases)
    func failedOperationRetainsDraftAndRetry(_ operation: FileOperationFailureFixture) async throws {
        _ = NSApplication.shared
        let vaultID = UUID()
        let note = NoteMutationTarget(
            documentID: .init(vaultID: vaultID, relativePath: "Research/Origin.md"),
            stableNoteID: UUID(), revision: .init(content: "Synthetic source"))
        let folder = FolderMutationTarget(vaultID: vaultID, relativePath: "Research/Origin")
        let firstReason = "The destination already exists. Choose another location. 目标已存在。"
        let secondReason = "The destination could not be verified. Retry after checking the location."
        var submittedPaths: [String] = []
        let submit: @MainActor (String) async throws -> Void = { path in
            submittedPaths.append(path)
            throw FileOperationFixtureError(message: submittedPaths.count == 1 ? firstReason : secondReason)
        }
        let content: AnyView
        switch operation {
        case .moveNote, .duplicateNote:
            content = AnyView(
                NoteFileOperationView(
                    request: operation == .moveNote ? .move(note) : .duplicate(note),
                    actions: .init(duplicate: { _, path in try await submit(path) }, move: { _, path in try await submit(path) })))
        case .renameFolder, .moveFolder:
            content = AnyView(
                FolderFileOperationView(
                    request: operation == .renameFolder ? .rename(folder) : .move(folder),
                    folderRelativePaths: ["Research", "Collision", "Corrected"],
                    actions: .init(move: { _, path in try await submit(path) })))
        }
        // This regression uses a presented native sheet for accessibility interaction.
        // The display-evidence gate keeps this foreground fixture out of headless regression runs.
        let host = NSHostingView(
            rootView: Color.clear.sheet(isPresented: .constant(true)) {
                content.environment(\.locale, Locale(identifier: "en")).frame(width: 320)
            })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
                sheet.close()
            }
            window.contentView = nil
            window.close()
        }
        try await settleForm(host, phase: "native sheet presentation") { window.attachedSheet != nil }
        let sheet = try #require(window.attachedSheet)
        let form = try #require(sheet.contentView)
        try await settleForm(form, phase: "editable control construction") {
            self.editableControlIfPresent(in: form, operation: operation) != nil
        }
        try setDraft("Collision", in: form, operation: operation)
        try await settleForm(form, phase: "edited draft admission") { self.commitIsEnabled(in: form, operation: operation) }
        try pressCommit(in: form, operation: operation)
        try await settleForm(form, phase: "first inline failure") { self.errorText(in: form, operation: operation).contains(firstReason) }
        #expect(submittedPaths == [operation.path(for: "Collision")])
        #expect(sheet.attachedSheet == nil, "Failure must not cover the form with an alert")
        #expect(try draft(in: form, operation: operation) == operation.draft(for: "Collision"))
        #expect(try editableControl(in: form, operation: operation).isEnabled)
        #expect(commitIsEnabled(in: form, operation: operation))

        try setDraft("Corrected", in: form, operation: operation)
        try await settleForm(form, phase: "corrected draft retention") {
            (try? self.draft(in: form, operation: operation)) == operation.draft(for: "Corrected")
        }
        #expect(errorText(in: form, operation: operation).contains(firstReason), "Editing must retain the failure until retry")
        try pressCommit(in: form, operation: operation)
        try await settleForm(form, phase: "retried inline failure") { self.errorText(in: form, operation: operation).contains(secondReason) }
        #expect(submittedPaths == [operation.path(for: "Collision"), operation.path(for: "Corrected")])
        #expect(!errorText(in: form, operation: operation).contains(firstReason))
        #expect(try draft(in: form, operation: operation) == operation.draft(for: "Corrected"))
        #expect(try editableControl(in: form, operation: operation).isEnabled)
        #expect(sheet.attachedSheet == nil && window.attachedSheet === sheet)
    }

    private func commitElement(in host: NSView, operation: FileOperationFailureFixture) -> NSObject? {
        accessibilityDescendants(host).first {
            accessibilityValue("accessibilityIdentifier", of: $0) as? String == "scholium.\(operation.prefix).commit"
                && $0.responds(to: NSSelectorFromString("accessibilityPerformPress"))
        }
    }

    private func commitIsEnabled(in host: NSView, operation: FileOperationFailureFixture) -> Bool {
        guard let element = commitElement(in: host, operation: operation),
            element.responds(to: NSSelectorFromString("isAccessibilityEnabled"))
        else { return false }
        return element.value(forKey: "accessibilityEnabled") as? Bool == true
    }

    private func pressCommit(in host: NSView, operation: FileOperationFailureFixture) throws {
        let element = try #require(commitElement(in: host, operation: operation))
        let button = try #require(element as? NSAccessibilityProtocol)
        #expect(button.accessibilityPerformPress())
    }

    private func editableControl(in host: NSView, operation: FileOperationFailureFixture) throws -> NSControl {
        try #require(editableControlIfPresent(in: host, operation: operation))
    }

    private func editableControlIfPresent(in host: NSView, operation: FileOperationFailureFixture) -> NSControl? {
        if operation == .moveFolder {
            return descendants(host).compactMap { $0 as? NSPopUpButton }.first
        }
        return descendants(host).compactMap { $0 as? NSTextField }.first { $0.isEditable }
    }

    private func draft(in host: NSView, operation: FileOperationFailureFixture) throws -> String {
        let control = try editableControl(in: host, operation: operation)
        if let picker = control as? NSPopUpButton { return picker.titleOfSelectedItem ?? "" }
        return control.stringValue
    }

    private func setDraft(_ value: String, in host: NSView, operation: FileOperationFailureFixture) throws {
        let control = try editableControl(in: host, operation: operation)
        if let picker = control as? NSPopUpButton {
            picker.selectItem(withTitle: value)
            #expect(picker.sendAction(picker.action, to: picker.target))
        } else {
            let field = try #require(control as? NSTextField)
            field.stringValue = operation.draft(for: value)
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        }
    }

    private func errorText(in host: NSView, operation: FileOperationFailureFixture) -> String {
        let identifier = "scholium.\(operation.prefix).error"
        guard
            let error = accessibilityDescendants(host).first(where: {
                accessibilityValue("accessibilityIdentifier", of: $0) as? String == identifier
            })
        else { return "" }
        return accessibilityDescendants(error).flatMap { element in
            ["accessibilityLabel", "accessibilityValue"].compactMap { accessibilityValue($0, of: element) as? String }
        }.joined(separator: " ")
    }

    private func accessibilityValue(_ key: String, of element: NSObject) -> Any? {
        guard element.responds(to: NSSelectorFromString(key)) else { return nil }
        return element.value(forKey: key)
    }

    private func accessibilityDescendants(_ root: NSObject) -> [NSObject] {
        var remaining = [root]
        var result: [NSObject] = []
        var visited: Set<ObjectIdentifier> = []
        while let element = remaining.popLast() {
            guard visited.insert(ObjectIdentifier(element)).inserted else { continue }
            result.append(element)
            remaining.append(contentsOf: accessibilityValue("accessibilityChildren", of: element) as? [NSObject] ?? [])
            if let view = element as? NSView { remaining.append(contentsOf: view.subviews) }
        }
        return result
    }

    private func settleForm(_ host: NSView, phase: String, until predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        repeat {
            host.layoutSubtreeIfNeeded()
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        let controls = descendants(host).compactMap { $0 as? NSControl }.map {
            "\(type(of: $0)): \($0.accessibilityIdentifier())"
        }.joined(separator: ", ")
        let elements = accessibilityDescendants(host).prefix(24).map { element in
            let details = ["accessibilityIdentifier", "accessibilityRole", "accessibilityLabel", "accessibilityValue"].compactMap {
                accessibilityValue($0, of: element).map(String.init(describing:))
            }.joined(separator: " | ")
            return "\(type(of: element)): \(details)"
        }.joined(separator: "; ")
        throw FileOperationFixtureError(message: "Hosted form timed out during \(phase). Native controls: \(controls). Accessibility: \(elements)")
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}

@MainActor
private final class SheetInsetMarkers {
    var views: [String: NSView] = [:]
}

@Observable
@MainActor
private final class SheetFixtureState {
    var isLoading = true
}

private struct SheetInsetMarker: NSViewRepresentable {
    let name: String
    let markers: SheetInsetMarkers

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        markers.views[name] = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum FileOperationFailureFixture: String, CaseIterable, Sendable {
    case moveNote, duplicateNote, renameFolder, moveFolder

    var prefix: String { self == .moveNote || self == .duplicateNote ? "noteFile" : "folderFile" }

    func draft(for name: String) -> String {
        self == .moveNote || self == .duplicateNote ? "Research/" + name + ".md" : name
    }

    func path(for name: String) -> String {
        switch self {
        case .moveNote, .duplicateNote: draft(for: name)
        case .renameFolder: "Research/" + name
        case .moveFolder: name + "/Origin"
        }
    }
}

private struct FileOperationFixtureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
