import AppKit
import Combine
import Foundation
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

@Suite("Isolated Zotero original access settings", .serialized)
@MainActor
struct ZoteroOriginalAccessSettingsTests {
    @Test("Selecting the library folder grants nested originals, retains exact restore scope and revokes only access")
    func modelGrantWorkflow() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let state = State()
        let model = await makeModel(fixture, state: state)
        #expect(try await model.zoteroOriginalAccessGrants().isEmpty)
        let located = try #require(try await model.suggestedZoteroOriginalLibraryDirectory())
        #expect(located.path == fixture.library.path)
        let request = ZoteroOriginalAccessSettingsView.selectionRequest(
            kind: .folder, locatedLibraryURL: located, locale: Locale(identifier: "zh-Hans"))
        let panel = request.makePanel()
        #expect(panel.directoryURL?.path == fixture.library.path)
        #expect(panel.prompt == "允许读取")
        #expect(panel.message.contains("Zotero 已定位此文献库文件夹"))
        #expect(panel.canChooseDirectories && !panel.canChooseFiles && !panel.canCreateDirectories)
        #expect(try await model.zoteroOriginalAccessGrants().isEmpty, "A directory hint must not create access")
        let presenter = ScholiumFileSelectionPresenter()
        do {
            _ = try await presenter.selectURL(.init(kind: .directory(canCreateDirectories: false)))
            Issue.record("A chooser without its scene window must refuse presentation")
        } catch let error as ScholiumFileSelectionError { #expect(error == .presenterUnavailable) }
        #expect(try await model.zoteroOriginalAccessGrants().isEmpty)

        let selection = ScholiumFileSelectionRequest(kind: .directory(canCreateDirectories: false))
        let selected = try #require(selection.validatedURLs([fixture.library]).first)
        try await model.authorizeZoteroOriginalAccess(selectedURL: selected, replacing: nil)
        let grant = try #require(try await model.zoteroOriginalAccessGrants().first)
        let restore = ZoteroOriginalAccessSettingsView.selectionRequest(
            kind: .folder, grant: grant, locatedLibraryURL: fixture.support, locale: Locale(identifier: "en"))
        #expect(restore.initialDirectoryURL == fixture.library.deletingLastPathComponent())
        #expect(restore.message == "Select the same file or folder to restore read-only access.")
        #expect(grant.path == fixture.library.path && grant.status == .available)
        let original = try await readOriginal(fixture)
        #expect(original["original_file_read"] == .bool(true))
        #expect(original["text"] == .string(String(decoding: fixture.bytes, as: UTF8.self)))
        await #expect(throws: ZoteroOriginalAccessError.self) {
            try await model.authorizeZoteroOriginalAccess(selectedURL: fixture.support, replacing: grant.id)
        }
        #expect(try await model.zoteroOriginalAccessGrants().first?.id == grant.id)
        try await model.authorizeZoteroOriginalAccess(selectedURL: selected, replacing: grant.id)
        #expect(try await model.zoteroOriginalAccessGrants().first?.id == grant.id)
        state.readFailure = true
        await #expect(throws: ZoteroOriginalAccessError.self) { try await model.zoteroOriginalAccessGrants() }
        state.readFailure = false
        #expect(try await model.zoteroOriginalAccessGrants().first?.id == grant.id)
        try await model.removeZoteroOriginalAccess(grantID: grant.id)
        #expect(try await model.zoteroOriginalAccessGrants().isEmpty)
        #expect(try await readOriginal(fixture, failed: true)["error_code"] == .string("original_permission_denied"))
        #expect(try Data(contentsOf: fixture.original) == fixture.bytes)
        #expect(try Data(contentsOf: fixture.libraryDatabase) == fixture.databaseBytes)
        #expect(state.desktopCalls == 0)
    }

    @Test("The isolated permission group renders at minimum width with adapted grant and localized error states")
    func isolatedNativePresentation() async throws {
        _ = NSApplication.shared
        let fixture = try Fixture()
        defer { fixture.remove() }
        let state = State()
        let model = await makeModel(fixture, state: state)
        let presenter = ScholiumFileSelectionPresenter()
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Fixture Original Access Settings"
        window.contentView = host
        window.orderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        let output = fixture.repository.appendingPathComponent(".build/zotero-workflow/original-access-ui")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let scenarios: [(name: String, narrow: Bool, failure: Bool)] = [
            ("empty-light", false, false),
            ("populated-minimum-contrast-dark-enlarged", true, false),
            ("error-minimum-chinese", true, true),
        ]
        for scenario in scenarios {
            if scenario.name == "populated-minimum-contrast-dark-enlarged" {
                try await model.authorizeZoteroOriginalAccess(selectedURL: fixture.library, replacing: nil)
                try await model.authorizeZoteroOriginalAccess(selectedURL: fixture.original, replacing: nil)
                try FileManager.default.moveItem(at: fixture.original, to: fixture.originals.appendingPathComponent("Moved fixture.txt"))
                try fixture.bytes.write(to: fixture.original)
            }
            state.readFailure = scenario.failure
            let expectedLoad = state.loads + 1
            let dark = scenario.name == "populated-minimum-contrast-dark-enlarged"
            let chinese = scenario.failure
            let width = scenario.narrow ? ScholiumMetrics.Settings.minimumWindowWidth : 980
            let root = Form { ZoteroOriginalAccessSettingsView() }
                .scholiumSettingsFormStyle()
                .scholiumSettingsPaneSurface()
                .environmentObject(model)
                .environment(\.scholiumSettingsPaneIsActive, true)
                .environment(\.locale, Locale(identifier: chinese ? "zh-Hans" : "en"))
                .environment(\.colorScheme, dark ? .dark : .light)
                .dynamicTypeSize(dark ? .accessibility1 : .large)
                .font(.system(size: dark ? 20 : NSFont.systemFontSize))
                .scholiumFileSelectionScene(presenter: presenter)
                .id(scenario.name)
            host.rootView = AnyView(root)
            host.appearance = NSAppearance(named: dark ? .accessibilityHighContrastDarkAqua : .aqua)
            window.setContentSize(NSSize(width: width, height: 760))
            try await waitUntil { state.loads >= expectedLoad }
            // The model callback is complete; allow native layout publication.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            host.layoutSubtreeIfNeeded()
            #expect(presenter.presentationWindow === window)
            #expect(abs(host.bounds.width - width) < 0.5)
            for button in descendants(host).compactMap({ $0 as? NSButton }) where !button.isHiddenOrHasHiddenAncestor {
                let frame = button.convert(button.bounds, to: host)
                #expect(frame.minX >= -1 && frame.maxX <= width + 1)
            }
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent(scenario.name + ".png"))
        }
        #expect(state.desktopCalls == 0, "Rendering original access must not query the real Zotero Desktop API")
        print(
            "Original access Settings: three isolated render states retained; native presenter bound to the fixture window. SwiftUI accessibility transport, native picker input and physical assistive-technology acceptance are unavailable in this unit host."
        )
    }

    @Test("Original access controls and recovery errors resolve English and Chinese from their owned catalogs")
    func localizedControlAndRecoveryCopy() {
        let chinese = Locale(identifier: "zh-Hans")
        let controls: [(String.LocalizationValue, String)] = [
            ("Original File Access", "原文文件访问"),
            ("Choose Zotero Library Folder…", "选择 Zotero 文献库文件夹…"),
            ("Add Original File…", "添加原文文件…"),
            ("Restore Original Access…", "恢复原文访问权限…"),
            ("Remove Original Access", "移除原文访问权限"),
            ("Reload Original Access", "重新载入原文访问权限"),
        ]
        for (key, expected) in controls {
            #expect(ScholiumL10n.string(key, locale: chinese) == expected)
            #expect(ScholiumL10n.string(key, locale: Locale(identifier: "en")) != expected)
        }
        let errors: [(String.LocalizationValue, String)] = [
            ("Original access settings are unavailable. Reopen Scholium and try again.", "原文访问设置不可用。请重新打开 Scholium 后重试。"),
            ("Original access settings cannot be read. Existing settings were preserved.", "无法读取原文访问设置。现有设置已保留。"),
            ("Select an original file or its folder directly. Symbolic links are not supported.", "请直接选择原文文件或其文件夹。不支持符号链接。"),
            ("This original access grant was removed. Reload the list and try again.", "此原文访问权限已被移除。请重新载入列表后重试。"),
        ]
        for (key, expected) in errors {
            #expect(String(localized: LocalizedStringResource(key, table: "Interface", locale: chinese, bundle: .module)) == expected)
        }
    }

    @Test("Unavailable directory discovery retains manual folder and exact file routes")
    func manualSelectionFallback() {
        let locale = Locale(identifier: "zh-Hans")
        let folder = ZoteroOriginalAccessSettingsView.selectionRequest(kind: .folder, locale: locale)
        #expect(folder.initialDirectoryURL == nil)
        #expect(folder.message?.contains("未能定位文献库文件夹") == true)
        #expect(folder.message?.contains("手动选择") == true)
        #expect(folder.makePanel().canChooseDirectories)
        let file = ZoteroOriginalAccessSettingsView.selectionRequest(
            kind: .file, locatedLibraryURL: URL(fileURLWithPath: "/Nonprivate"), locale: locale)
        #expect(file.initialDirectoryURL == nil)
        #expect(file.makePanel().canChooseFiles && !file.makePanel().canChooseDirectories)
        #expect(file.message == "请选择原文文件，以授予只读权限。")
    }

    private func makeModel(_ fixture: Fixture, state: State) async -> WorkspaceSettingsModel {
        let styles = CSSSnippetStore(operations: StyleOperations(applicationSupportURL: fixture.support))
        await styles.refresh()
        return WorkspaceSettingsModel(
            capabilities: .init(
                workspace: .init(
                    loadSnapshot: { _ in .init() },
                    configureWorkspace: { _, _, _, _, _, _ in throw UnexpectedOperation() },
                    loadSettingsRecovery: { _ in throw UnexpectedOperation() },
                    resetTriptychSettings: { _, _ in throw UnexpectedOperation() },
                    portableContainerURL: { _ in nil }
                ),
                zotero: .init(
                    zoteroConnectionInfo: {
                        state.desktopCalls += 1
                        return .init(status: .appUnavailable, lastSuccessfulConnection: nil)
                    },
                    openZotero: { state.desktopCalls += 1 },
                    clearZoteroConnectionHistory: { state.desktopCalls += 1 },
                    refreshZoteroLibraryInfo: {
                        state.desktopCalls += 1
                        throw UnexpectedOperation()
                    },
                    originalAccessGrants: {
                        defer { state.loads += 1 }
                        if state.readFailure { throw ZoteroOriginalAccessError.damagedConfiguration }
                        return try await fixture.zotero.originalAccessGrants()
                    },
                    suggestedOriginalLibraryDirectory: { try await fixture.zotero.suggestedOriginalLibraryDirectory() },
                    authorizeOriginalAccess: { try await fixture.zotero.authorizeOriginalAccess(selectedURL: $0, replacing: $1) },
                    removeOriginalAccess: { try await fixture.zotero.removeOriginalAccess(grantID: $0) }
                ),
                changesHistory: .init(
                    updates: Empty().eraseToAnyPublisher(),
                    load: { _ in throw UnexpectedOperation() },
                    setRetention: { _, _ in throw UnexpectedOperation() },
                    clear: { _ in throw UnexpectedOperation() }
                ),
                storage: .init(
                    inventory: { throw UnexpectedOperation() },
                    perform: { _, _ in throw UnexpectedOperation() },
                    archivedChats: { _ in throw UnexpectedOperation() },
                    deleteArchivedChats: { _ in throw UnexpectedOperation() },
                    unusedChatMaterials: { _ in throw UnexpectedOperation() },
                    trashUnusedChatMaterials: { _ in throw UnexpectedOperation() }
                )
            ),
            cssSnippetStore: styles
        )
    }

    private func readOriginal(_ fixture: Fixture, failed: Bool = false) async throws -> [String: MCPJSONValue] {
        let request = MCPJSONValue.object([
            "jsonrpc": .string("2.0"), "id": .integer(1), "method": .string("tools/call"),
            "params": .object([
                "name": .string("zotero_read_original_file"),
                "arguments": .object(["library": .string("user"), "attachment_key": .string("ATTACH01"), "mode": .string("text")]),
            ]),
        ])
        let response = try #require(await fixture.zotero.handle(requestData: JSONEncoder().encode(request), access: .readOnly))
        let result = try #require(try JSONDecoder().decode(MCPJSONValue.self, from: response).objectValue?["result"]?.objectValue)
        #expect(result["isError"] == .bool(failed))
        return try #require(result["structuredContent"]?.objectValue)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(predicate(), "The isolated Settings host did not publish its native state")
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private struct UnexpectedOperation: Error {}
    private final class State {
        var desktopCalls = 0
        var loads = 0
        var readFailure = false
    }

    private struct Fixture {
        let repository: URL
        let root: URL
        let support: URL
        let library: URL
        let libraryDatabase: URL
        let originals: URL
        let original: URL
        let bytes = Data("Nonprivate original fixture.\r\n".utf8)
        let databaseBytes = Data("A disposable database marker, never opened by Scholium.".utf8)
        let zotero: ZoteroOperations

        init() throws {
            repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            root = repository.appendingPathComponent(".build/zotero-original-access-settings/\(UUID())")
            support = root.appendingPathComponent("Support")
            library = root.appendingPathComponent("Zotero Library 文献库 — fixture with nested originals")
            libraryDatabase = library.appendingPathComponent("zotero.sqlite")
            originals = library.appendingPathComponent("storage/ATTACH01")
            original = originals.appendingPathComponent("A source with a complete descriptive filename 原文.txt")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
            try bytes.write(to: original)
            try databaseBytes.write(to: libraryDatabase)
            let originalURL = original
            zotero = ZoteroOperations(
                applicationSupportURL: support,
                mcpRequestLoader: { request in
                    guard let url = request.url, request.httpMethod == "GET", url.host == "127.0.0.1" else { throw UnexpectedOperation() }
                    let body: Data
                    switch url.path {
                    case "/api/users/0/items":
                        body = try JSONSerialization.data(withJSONObject: [
                            [
                                "key": "ATTACH01", "version": 1,
                                "data": [
                                    "key": "ATTACH01", "itemType": "attachment", "parentItem": "PARENT01",
                                    "linkMode": "imported_file", "contentType": "text/plain", "filename": originalURL.lastPathComponent,
                                ],
                            ]
                        ])
                    case "/api/users/0/items/ATTACH01/file/view/url":
                        body = Data(originalURL.absoluteString.utf8)
                    case "/api/users/0/items/ATTACH01":
                        body = try JSONSerialization.data(withJSONObject: [
                            "key": "ATTACH01", "version": 1,
                            "data": [
                                "key": "ATTACH01", "itemType": "attachment", "parentItem": "PARENT01",
                                "linkMode": "imported_file", "contentType": "text/plain", "filename": originalURL.lastPathComponent,
                            ],
                        ])
                    default: throw UnexpectedOperation()
                    }
                    let response = try #require(
                        HTTPURLResponse(
                            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                            headerFields: ["Zotero-Server-ID": "fixture-server", "Last-Modified-Version": "1"]
                        ))
                    return (body, response)
                })
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
