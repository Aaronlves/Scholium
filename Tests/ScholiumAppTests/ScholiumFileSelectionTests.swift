import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ScholiumApp

@Suite("Scholium file selection")
@MainActor
struct ScholiumFileSelectionTests {
    @Test("Typed requests configure the native panel without workflow policy")
    func requestConfiguration() {
        let directory = URL(fileURLWithPath: "/example", isDirectory: true)
        let markdown = UTType(filenameExtension: "md") ?? .plainText
        let request = ScholiumFileSelectionRequest(
            title: "Choose Markdown",
            message: "Choose one source.",
            prompt: "Choose",
            initialDirectoryURL: directory,
            kind: .files(
                allowedContentTypes: [markdown],
                resolvesAliases: false
            )
        )

        let panel = request.makePanel()
        #expect(panel.title == "Choose Markdown")
        #expect(panel.message == "Choose one source.")
        #expect(panel.prompt == "Choose")
        #expect(panel.directoryURL == directory)
        #expect(panel.canChooseFiles)
        #expect(!panel.canChooseDirectories)
        #expect(!panel.canCreateDirectories)
        #expect(!panel.allowsMultipleSelection)
        #expect(!panel.resolvesAliases)
        #expect(panel.allowedContentTypes == [markdown])
    }

    @Test("Exact folder authorization rejects siblings and normalizes aliases")
    func exactDirectoryValidation() throws {
        let fixtureRoot = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let expected = fixtureRoot.appendingPathComponent("Expected", isDirectory: true)
        let sibling = fixtureRoot.appendingPathComponent("Sibling", isDirectory: true)
        let alias = fixtureRoot.appendingPathComponent("Expected Alias", isDirectory: true)
        let ordinaryFile = fixtureRoot.appendingPathComponent("ordinary.md")
        try FileManager.default.createDirectory(at: expected, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: expected)
        try Data("source".utf8).write(to: ordinaryFile)

        let request = ScholiumFileSelectionRequest(
            kind: .directory(canCreateDirectories: false),
            constraint: .exactCanonicalDirectory(
                expected,
                rejectionMessage: "Choose Expected."
            )
        )
        let canonicalExpected = expected.resolvingSymlinksInPath().standardizedFileURL

        #expect(try request.validatedURLs([expected]) == [canonicalExpected])
        #expect(try request.validatedURLs([alias]) == [canonicalExpected])

        do {
            _ = try request.validatedURLs([sibling])
            Issue.record("A sibling directory must not satisfy exact authorization.")
        } catch let error as ScholiumFileSelectionError {
            #expect(error == .rejectedSelection(message: "Choose Expected."))
        }

        do {
            _ = try request.validatedURLs([ordinaryFile])
            Issue.record("A file must not satisfy a directory request.")
        } catch let error as ScholiumFileSelectionError {
            #expect(error == .wrongItemKind)
        }
    }

    @Test("Every native Open panel is owned by the scene presenter")
    func openPanelConstructionBoundary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = repositoryRoot.appendingPathComponent("Scholium", isDirectory: true)
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            )
        )
        var nativePanelOwners: [String] = []
        var requestOwners: [String: Int] = [:]
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            let relativePath = String(
                url.path.dropFirst(sourceRoot.path.count + 1)
            )
            if source.contains("NSOpenPanel") {
                nativePanelOwners.append(relativePath)
            }
            let requestCount = source.components(
                separatedBy: "ScholiumFileSelectionRequest("
            ).count - 1
            if requestCount > 0 {
                requestOwners[relativePath] = requestCount
                if relativePath != "App/ScholiumApp.swift" {
                    #expect(source.contains(
                        "@Environment(\\.scholiumFileSelectionPresenter)"
                    ))
                }
            }
            for forbiddenAPI in [
                "NSSavePanel(",
                ".fileImporter(",
                ".fileExporter(",
            ] {
                #expect(
                    !source.contains(forbiddenAPI),
                    "\(relativePath) bypasses the scene-owned file-selection presenter with \(forbiddenAPI)"
                )
            }
            #expect(!source.contains("panel.runModal()"))
        }

        #expect(nativePanelOwners == ["UI/Components/ScholiumFileSelection.swift"])
        #expect(requestOwners == [
            "App/ScholiumApp.swift": 1,
            "Views/Note/NoteContentView.swift": 2,
            "Views/RestoreWorkspaceAccessView.swift": 1,
            "Views/WorkspaceSettingsView.swift": 3,
            "Views/WorkspaceSetupView.swift": 2,
        ])

        let appSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("App/ScholiumApp.swift"),
            encoding: .utf8
        )
        #expect(
            appSource.components(
                separatedBy: ".scholiumFileSelectionScene("
            ).count == 4
        )
        #expect(appSource.contains("fileSelectionPresenter.selectURLs("))

        let workspaceRootStart = try #require(appSource.range(
            of: "private struct ScholiumWindowObservedRoot"
        ))
        let settingsRootStart = try #require(appSource.range(
            of: "private struct ScholiumSettingsRoot",
            range: workspaceRootStart.upperBound..<appSource.endIndex
        ))
        let workspaceRoot = appSource[
            workspaceRootStart.lowerBound..<settingsRootStart.lowerBound
        ]
        let recoverySheet = try #require(workspaceRoot.range(of: ".sheet(item:"))
        let sceneOwner = try #require(workspaceRoot.range(
            of: ".scholiumFileSelectionScene("
        ))
        #expect(
            recoverySheet.lowerBound < sceneOwner.lowerBound,
            "Restore Access must remain inside the scene presenter's environment boundary."
        )
    }

    @Test("A stale attachment cannot detach the current scene window")
    func staleAttachmentCannotDetachCurrentWindow() {
        let presenter = ScholiumFileSelectionPresenter()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let firstAttachment = ScholiumFileSelectionAttachmentView()
        firstAttachment.presenter = presenter
        window.contentView?.addSubview(firstAttachment)
        #expect(presenter.presentationWindow === window)

        let replacementAttachment = ScholiumFileSelectionAttachmentView()
        replacementAttachment.presenter = presenter
        window.contentView?.addSubview(replacementAttachment)
        #expect(presenter.presentationWindow === window)

        firstAttachment.removeFromSuperview()
        #expect(
            presenter.presentationWindow === window,
            "Removing an obsolete SwiftUI attachment must not clear the replacement binding."
        )

        replacementAttachment.removeFromSuperview()
        #expect(presenter.presentationWindow == nil)
    }

    @Test("Replacing a presenter detaches only the attachment's former owner")
    func replacingPresenterTransfersWindowOwnership() {
        let originalPresenter = ScholiumFileSelectionPresenter()
        let replacementPresenter = ScholiumFileSelectionPresenter()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let attachment = ScholiumFileSelectionAttachmentView()
        attachment.presenter = originalPresenter
        window.contentView?.addSubview(attachment)
        #expect(originalPresenter.presentationWindow === window)

        attachment.presenter = replacementPresenter
        #expect(originalPresenter.presentationWindow == nil)
        #expect(replacementPresenter.presentationWindow === window)

        attachment.removeFromSuperview()
        #expect(replacementPresenter.presentationWindow == nil)
    }

    @Test("Selection follows the scene window's currently attached sheet")
    func selectionUsesAttachedSheet() {
        let presenter = ScholiumFileSelectionPresenter()
        let sceneWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let featureSheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let attachment = ScholiumFileSelectionAttachmentView()
        attachment.presenter = presenter
        sceneWindow.contentView?.addSubview(attachment)

        sceneWindow.beginSheet(featureSheet)
        #expect(sceneWindow.attachedSheet === featureSheet)
        #expect(
            presenter.presentationWindow === featureSheet,
            "A chooser requested from Restore Access or another feature sheet must attach to that sheet."
        )

        sceneWindow.endSheet(featureSheet)
        #expect(presenter.presentationWindow === sceneWindow)
    }

    private func makeFixtureRoot() throws -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let parent = repositoryRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("file-selection-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let root = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
