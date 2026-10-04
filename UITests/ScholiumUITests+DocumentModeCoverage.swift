import AppKit
@preconcurrency import XCTest

extension ScholiumUITests {
    @MainActor
    func testWindowDocumentModeStaysSelectedAcrossTabsAndTriptychRoles() throws {
        let fixture = try prepareWindowModeFixture(appearance: .light)
        let window = stableWorkspaceWindow(app.windows.firstMatch)
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        selectDocumentMode("Source", in: window)
        let sourceEditor = window.descendants(matching: .any)["Markdown source editor"].firstMatch
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 10))
        // CodeMirror exposes its mounted lines through AX, not the complete
        // source. Focus the visible viewport, then navigate to the lower line.
        window.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).click()
        sourceEditor.typeKey(.end, modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { (sourceEditor.value as? String)?.contains("LEFT|RIGHT") == true })
        for _ in 0..<5 { sourceEditor.typeKey(.leftArrow, modifierFlags: []) }
        let draft = "中文 draft "
        let draftSource = fixture.source.replacingOccurrences(of: "LEFT|RIGHT", with: "LEFT|\(draft)RIGHT")
        try pasteWindowModeTextAtSelection(draft, into: sourceEditor)
        XCTAssertTrue(waitUntil(timeout: 8) { (sourceEditor.value as? String)?.contains("LEFT|\(draft)RIGHT") == true })
        try assertWindowModeIntermediateSourceBytes(fixture, candidate: draftSource, at: noteURL)
        assertWindowModeLowerPassageVisible(in: window)
        let sourceContext = try captureWindowModeViewportParagraph(in: window)

        openWindowModeNoteInNewTab("QA Autosave B.md", title: "QA Autosave B", in: window)
        assertWindowMode("Source", in: window)
        activateWindowModeTab("QA Autosave A", in: window)
        assertWindowMode("Source", in: window)
        XCTAssertTrue(waitUntil(timeout: 8) { (sourceEditor.value as? String)?.contains("LEFT|\(draft)RIGHT") == true })
        try assertWindowModeIntermediateSourceBytes(fixture, candidate: draftSource, at: noteURL)
        assertWindowModeLowerPassageVisible(in: window)
        openWindowModeRoleNote("Topics", path: "QA Topic.md", title: "QA Topic", in: window)
        assertWindowMode("Source", in: window)
        openWindowModeRoleNote("Works", path: "QA Work.md", title: "QA Work", in: window)
        assertWindowMode("Source", in: window)

        // Only this explicit choice changes the window mode. The retained A
        // tab must adopt Edit while keeping its own source, caret, and scroll.
        selectDocumentMode("Edit", in: window)
        activateWindowModeTab("QA Autosave A", in: window)
        assertWindowMode("Edit", in: window)
        let edit = window.descendants(matching: .any)["Markdown editor, Edit mode"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        XCTAssertTrue((edit.value as? String)?.contains("LEFT|\(draft)RIGHT") == true)
        try assertWindowModeIntermediateSourceBytes(fixture, candidate: draftSource, at: noteURL)
        assertWindowModeViewportParagraph(sourceContext, in: window)
        XCTAssertTrue(
            waitUntil(timeout: 5) { NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: edit) },
            "Retained-tab activation must return keyboard focus to its editor."
        )
        let caretInsertion = "24680"
        // No editor click or navigation command may repair the retained caret.
        app.typeText(caretInsertion)
        let committed = fixture.source.replacingOccurrences(
            of: "LEFT|RIGHT", with: "LEFT|\(draft)\(caretInsertion)RIGHT"
        )
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                (edit.value as? String)?.contains("LEFT|\(draft)\(caretInsertion)RIGHT") == true
            }, "The next insertion must occur at A's retained source position after adopting Edit.")
        edit.typeKey("z", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 5) { (edit.value as? String)?.contains("LEFT|\(draft)RIGHT") == true })
        edit.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                (edit.value as? String)?.contains("LEFT|\(draft)\(caretInsertion)RIGHT") == true
            })
        edit.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 10) { (try? Data(contentsOf: noteURL)) == Data(committed.utf8) })
        captureWindowModeEvidence(window, name: "Window mode Edit retains bilingual draft, caret and document context")
        // Typing may reveal the retained caret. Capture the resulting reading
        // context before the separate Edit-to-Review handoff.
        let editContext = try captureWindowModeViewportParagraph(in: window)

        selectDocumentMode("Review", in: window)
        activateWindowModeTab("QA Topic", in: window)
        assertWindowMode("Review", in: window)
        activateWindowModeTab("QA Autosave A", in: window)
        assertWindowMode("Review", in: window)
        assertWindowModeViewportParagraph(editContext, in: window)
        XCTAssertEqual(try Data(contentsOf: noteURL), Data(committed.utf8))
        try assertWindowModePeerBytes(fixture)
    }

    @MainActor
    func testDetachedDocumentInheritsModeThenReturnsToIndependentDestinationModeWithUndo() throws {
        let fixture = try prepareWindowModeFixture(appearance: .dark)
        let main = stableWorkspaceWindow(app.windows.firstMatch)
        let mainID = main.identifier
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        selectDocumentMode("Source", in: main)
        let sourceEditor = main.descendants(matching: .any)["Markdown source editor"].firstMatch
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 10))
        main.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).click()
        sourceEditor.typeKey(.end, modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { (sourceEditor.value as? String)?.contains("LEFT|RIGHT") == true })
        for _ in 0..<5 { sourceEditor.typeKey(.leftArrow, modifierFlags: []) }
        let token = "转移 transfer "
        try pasteWindowModeTextAtSelection(token, into: sourceEditor)
        let edited = fixture.source.replacingOccurrences(of: "LEFT|RIGHT", with: "LEFT|\(token)RIGHT")
        XCTAssertTrue(waitUntil(timeout: 8) { (sourceEditor.value as? String)?.contains("LEFT|\(token)RIGHT") == true })
        try assertWindowModeIntermediateSourceBytes(fixture, candidate: edited, at: noteURL)
        let sourceContext = try captureWindowModeViewportParagraph(in: main)
        openWindowModeNoteInNewTab("QA Autosave B.md", title: "QA Autosave B", in: main)
        activateWindowModeTab("QA Autosave A", in: main)
        assertWindowMode("Source", in: main)
        try assertWindowModeIntermediateSourceBytes(fixture, candidate: edited, at: noteURL)
        assertWindowModeLowerPassageVisible(in: main)
        focusWorkspaceWindow(main)
        app.menuBars.menuBarItems["Window"].click()
        let moveOut = app.menuItems["Move to Separate Window"].firstMatch
        XCTAssertTrue(moveOut.waitForExistence(timeout: 5) && moveOut.isEnabled)
        moveOut.click()
        XCTAssertTrue(waitUntil(timeout: 12) { self.app.windows.count == 2 })
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", in: main, timeout: 10))
        let detachedID = try XCTUnwrap(
            app.windows.allElementsBoundByIndex.first {
                $0.identifier != mainID && $0.title == "QA Autosave A"
            }?.identifier)
        let detached = app.windows[detachedID]
        XCTAssertFalse(windowModeTab("QA Autosave A", in: main).exists)
        assertWindowMode("Source", in: detached)
        assertWindowModeLowerPassageVisible(in: detached)
        assertWindowModeViewportParagraph(sourceContext, in: detached)
        let detachedSource = detached.descendants(matching: .any)["Markdown source editor"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 8) { (detachedSource.value as? String)?.contains("LEFT|\(token)RIGHT") == true })
        try assertWindowModeIntermediateSourceBytes(fixture, candidate: edited, at: noteURL)
        let detachedContext = try captureWindowModeViewportParagraph(in: detached)

        // The populated main window changes independently. The detached
        // window's subsequent explicit choices must not alter the receiver.
        selectDocumentMode("Edit", in: main)
        assertWindowMode("Source", in: detached)
        selectDocumentMode("Review", in: detached)
        assertWindowMode("Edit", in: main)
        assertWindowMode("Review", in: detached)
        assertWindowModeViewportParagraph(detachedContext, in: detached)
        // Separate Document windows expose Review/Edit choices. Return from
        // Review to the populated receiver's independent Edit choice.
        focusWorkspaceWindow(detached)
        app.menuBars.menuBarItems["Window"].click()
        let moveBack = app.menuItems["Move to Main Window"].firstMatch
        XCTAssertTrue(moveBack.waitForExistence(timeout: 5) && moveBack.isEnabled)
        moveBack.click()
        XCTAssertTrue(waitUntil(timeout: 12) { !detached.exists && self.app.windows.count == 1 })
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", in: main, timeout: 10))
        assertWindowMode("Edit", in: main)
        assertWindowModeViewportParagraph(detachedContext, in: main)
        let returned = main.descendants(matching: .any)["Markdown editor, Edit mode"].firstMatch
        XCTAssertTrue(returned.waitForExistence(timeout: 8))
        XCTAssertTrue((returned.value as? String)?.contains("LEFT|\(token)RIGHT") == true)
        try assertWindowModeIntermediateSourceBytes(fixture, candidate: edited, at: noteURL)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: returned)
            })
        // This Undo entry was created in Source before either transfer. It
        // proves that adoption preserved the live editor session, not bytes alone.
        returned.typeKey("z", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { (returned.value as? String)?.contains("LEFT|RIGHT") == true })
        returned.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 10) { (try? Data(contentsOf: noteURL)) == Data(fixture.source.utf8) })
        returned.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitUntil(timeout: 8) { (returned.value as? String)?.contains("LEFT|\(token)RIGHT") == true })
        returned.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 10) { (try? Data(contentsOf: noteURL)) == Data(edited.utf8) })
        XCTAssertTrue(windowModeTab("QA Autosave B", in: main).exists)
        captureWindowModeEvidence(main, name: "Dark transferred session adopts destination Edit and retains Undo")
        try assertWindowModePeerBytes(fixture)
    }

    @MainActor
    private func prepareWindowModeFixture(appearance: QAAppearance) throws -> WindowModeFixture {
        app.terminate()
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.state == .notRunning })
        let middle = (1...60).map {
            "Synthetic window mode paragraph \($0). 中文上下文 keeps this disposable Note long enough to expose viewport resets."
        }.joined(separator: "\n\n")
        let text =
            "---\nsummary: Synthetic window mode fixture.\nunknown_mode_field: 'KEEP: 原始'\n# Preserved comment\n---\n\n# Window mode opening marker\n\n\(middle)\n\n## Window mode lower marker\n\nLEFT|RIGHT"
        try Data(text.utf8).write(to: triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md"))
        let peers = try ["01-analyses/QA Autosave B.md", "02-topics/QA Topic.md", "03-works/QA Work.md"].map {
            let url = triptychDirectory.appendingPathComponent($0)
            return (url, try Data(contentsOf: url))
        }
        sessionID = UUID()
        app = configuredApplication(sessionID: sessionID, autosaveDelayMS: 300_000, appearance: appearance)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
        return WindowModeFixture(source: text, peerBytes: peers)
    }

    @MainActor
    private func openWindowModeNoteInNewTab(_ path: String, title: String, in window: XCUIElement) {
        _ = clickLibraryRow(path, in: window, rightMouseButton: true)
        let menu = app.menus["scholium.noteRow.\(path)"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.menuItems["Open in New Tab"].click()
        XCTAssertTrue(waitForDocumentTitle(title, in: window, timeout: 10))
    }

    @MainActor
    private func openWindowModeRoleNote(_ role: String, path: String, title: String, in window: XCUIElement) {
        let navigator = window.descendants(matching: .any)["scholium.workspaceNavigator"].firstMatch
        let currentTitle = documentTitle(in: window)
        navigator.descendants(matching: .any)[role].firstMatch.click()
        XCTAssertTrue(window.descendants(matching: .any)["scholium.noteRow.\(path)"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(documentTitle(in: window), currentTitle, "Browsing a role must not change the Document.")
        assertWindowMode("Source", in: window)
        openWindowModeNoteInNewTab(path, title: title, in: window)
    }

    @MainActor
    private func windowModeTab(_ title: String, in window: XCUIElement) -> XCUIElement {
        window.toolbars.firstMatch.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "scholium.documentTab.", title)
        ).firstMatch
    }

    @MainActor
    private func activateWindowModeTab(_ title: String, in window: XCUIElement) {
        let tab = windowModeTab(title, in: window)
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()
        XCTAssertTrue(waitForDocumentTitle(title, in: window, timeout: 10))
    }

    @MainActor
    private func assertWindowMode(_ title: String, in window: XCUIElement) {
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                self.documentModeState(self.documentModeControl(in: window)) == title
                    && self.windowModeSurface(title, in: window).exists
            }, "Navigation must retain this window's explicitly selected \(title) mode.")
    }

    @MainActor
    private func windowModeSurface(_ mode: String, in window: XCUIElement) -> XCUIElement {
        if mode == "Review" {
            return window.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND identifier != %@ AND identifier != %@",
                    "scholium.renderedDocument.", "scholium.renderedDocument.loading", "scholium.renderedDocument.failed"
                )
            ).firstMatch
        }
        return window.descendants(matching: .any)[
            mode == "Source" ? "Markdown source editor" : "Markdown editor, Edit mode"
        ].firstMatch
    }

    @MainActor
    private func captureWindowModeViewportParagraph(
        in window: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) throws -> String {
        let viewport = window.webViews.firstMatch
        let beginning = "Synthetic window mode paragraph "
        var captured: String?
        let found = waitUntil(timeout: 8) {
            guard viewport.exists else { return false }
            let bounds = viewport.frame
            let candidates = viewport.descendants(matching: .staticText).matching(
                NSPredicate(
                    format: "label BEGINSWITH %@ OR value BEGINSWITH %@ OR title BEGINSWITH %@",
                    beginning, beginning, beginning
                )
            ).allElementsBoundByIndex
            // Record authored content actually inside the upper/middle
            // viewport. The bottom marker can leave the viewport when Source
            // typography reflows into Edit or Review without losing context.
            let paragraphs = candidates.compactMap { candidate -> (String, CGRect)? in
                let frame = candidate.frame
                guard frame.minX.isFinite, frame.minY.isFinite,
                    frame.width.isFinite, frame.height.isFinite,
                    frame.width >= 8, frame.height >= 8,
                    bounds.contains(frame), candidate.isHittable,
                    frame.midY >= bounds.minY + bounds.height * 0.15,
                    frame.midY <= bounds.minY + bounds.height * 0.5
                else { return nil }
                for text in [candidate.value as? String, candidate.label, candidate.title].compactMap({ $0 }) {
                    if let prefix = text.range(
                        of: "^Synthetic window mode paragraph [0-9]+\\.", options: .regularExpression
                    ) {
                        return (String(text[prefix]), frame)
                    }
                }
                return nil
            }
            captured =
                paragraphs.min {
                    abs($0.1.midY - (bounds.minY + bounds.height * 0.25))
                        < abs($1.1.midY - (bounds.minY + bounds.height * 0.25))
                }?.0
            return captured != nil
        }
        XCTAssertTrue(found, "A fully visible authored paragraph must establish the outgoing document context.", file: file, line: line)
        let prefix = try XCTUnwrap(captured, file: file, line: line)
        print("DOCUMENT_MODE_CONTEXT_CAPTURE paragraph=\(prefix) viewport=\(viewport.frame)")
        return prefix
    }

    @MainActor
    private func assertWindowModeViewportParagraph(
        _ prefix: String, in window: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        let viewport = window.webViews.firstMatch
        func candidates() -> [XCUIElement] {
            viewport.descendants(matching: .staticText).matching(
                NSPredicate(
                    format: "label BEGINSWITH %@ OR value BEGINSWITH %@ OR title BEGINSWITH %@",
                    prefix, prefix, prefix
                )
            ).allElementsBoundByIndex
        }
        let retained = waitUntil(timeout: 8) {
            guard viewport.exists else { return false }
            return candidates().contains { candidate in
                let frame = candidate.frame
                guard frame.minX.isFinite, frame.minY.isFinite,
                    frame.width.isFinite, frame.height.isFinite, candidate.isHittable
                else { return false }
                let visible = frame.intersection(viewport.frame)
                return !visible.isNull && visible.width >= 8 && visible.height >= 8
            }
        }
        let geometry = candidates().prefix(3).map {
            "hittable=\($0.isHittable) frame=\($0.frame) visible=\($0.frame.intersection(viewport.frame))"
        }.joined(separator: "; ")
        print("DOCUMENT_MODE_CONTEXT_RETAINED paragraph=\(prefix) viewport=\(viewport.frame) \(geometry)")
        XCTAssertTrue(retained, "The same authored paragraph must remain visible across the document handoff.", file: file, line: line)
    }

    @MainActor
    private func assertWindowModeLowerPassageVisible(in window: XCUIElement) {
        let viewport = window.webViews.firstMatch
        func candidates() -> [XCUIElement] {
            let marker = "Window mode lower marker"
            let sourceMarker = "## " + marker
            // The always-present Outline button is outside this WebView. It
            // cannot establish that the actual lower passage is still visible.
            return viewport.descendants(matching: .staticText).matching(
                NSPredicate(
                    format: "label IN %@ OR value IN %@ OR title IN %@",
                    [marker, sourceMarker], [marker, sourceMarker], [marker, sourceMarker]
                )
            ).allElementsBoundByIndex
        }
        let retained = waitUntil(timeout: 8) {
            guard viewport.exists else { return false }
            return candidates().contains { candidate in
                let frame = candidate.frame
                guard frame.minX.isFinite, frame.minY.isFinite,
                    frame.width.isFinite, frame.height.isFinite, candidate.isHittable
                else { return false }
                let visible = frame.intersection(viewport.frame)
                return !visible.isNull && visible.width >= 8 && visible.height >= 8
            }
        }
        let snapshot = candidates()
        let geometry = snapshot.prefix(3).map {
            "hittable=\($0.isHittable) frame=\($0.frame) visible=\($0.frame.intersection(viewport.frame))"
        }.joined(separator: "; ")
        print(
            "DOCUMENT_MODE_VIEWPORT mode=\(documentModeState(documentModeControl(in: window)) ?? "unavailable") candidates=\(snapshot.count) viewport=\(viewport.frame) \(geometry)"
        )
        XCTAssertTrue(retained, "The retained lower passage must remain in the document viewport, rather than reset to the opening.")
    }

    @MainActor
    private func pasteWindowModeTextAtSelection(_ text: String, into editor: XCUIElement) throws {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                result[type] = item.data(forType: type)
            }
        }
        try setPasteboardText(text)
        let changeCount = pasteboard.changeCount
        defer {
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
                if let saved {
                    pasteboard.writeObjects(
                        saved.map { values in
                            let item = NSPasteboardItem()
                            for (type, bytes) in values { item.setData(bytes, forType: type) }
                            return item
                        })
                }
            }
        }
        editor.typeKey("v", modifierFlags: [.command])
    }

    @MainActor
    private func captureWindowModeEvidence(_ window: XCUIElement, name: String) {
        let image = XCTAttachment(screenshot: window.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    @MainActor
    private func assertWindowModeIntermediateSourceBytes(
        _ fixture: WindowModeFixture, candidate: String, at url: URL,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        // Navigation and mode handoffs may commit a draft before explicit Save.
        // Permit only those two exact whole-source states; unrelated byte changes
        // still fail, and the explicit Save/Undo boundaries below remain exact.
        let persisted = try Data(contentsOf: url)
        let original = Data(fixture.source.utf8)
        let edited = Data(candidate.utf8)
        let state = persisted == original ? "original" : (persisted == edited ? "draft" : "unexpected")
        print("DOCUMENT_MODE_SOURCE exactState=\(state) bytes=\(persisted.count)")
        XCTAssertTrue(
            persisted == original || persisted == edited,
            "Intermediate navigation must preserve the complete original or expected draft source bytes.",
            file: file, line: line)
    }

    @MainActor
    private func assertWindowModePeerBytes(_ fixture: WindowModeFixture) throws {
        for (url, bytes) in fixture.peerBytes { XCTAssertEqual(try Data(contentsOf: url), bytes) }
    }
}

private struct WindowModeFixture {
    let source: String
    let peerBytes: [(URL, Data)]
}
