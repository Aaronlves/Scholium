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
        let parent =
            repositoryRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("file-selection-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let root = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
