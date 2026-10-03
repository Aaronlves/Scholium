import AppKit
import CoreGraphics
import CoreText
import CryptoKit
import PDFKit
@preconcurrency import XCTest

extension ScholiumUITests {
    /// All enabled inactive tools share one native neutral foreground; state
    /// and accessibility remain distinct from hover, focus and window activity.
    @MainActor
    func testPDFReaderNativeToolForegroundConsistency() throws {
        let originalURL = testDirectory.appendingPathComponent("Synthetic Native Tool Foreground.pdf")
        try makeSearchableReaderPDF(at: originalURL)
        let original = try Data(contentsOf: originalURL)
        waitForCurrentDocumentSurface()
        app.typeKey("p", modifierFlags: [.control, .command])
        var main = app.windows.firstMatch
        var pane = main.descendants(matching: .any)["scholium.pdf.pane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 5))
        pane.buttons["scholium.pdf.attach"].click()
        app.buttons["scholium.pdf.chooseFile"].click()
        chooseReaderPDFInNativePanel(originalURL)
        XCTAssertTrue(main.textFields["scholium.pdf.page"].waitForExistence(timeout: 15))
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let boundSource = try source(at: noteURL)
        let managed = noteURL.deletingLastPathComponent().appendingPathComponent(try readerPDFBinding(in: boundSource))
        for dark in [false, true] {
            if dark {
                app.typeKey("q", modifierFlags: .command)
                XCTAssertTrue(waitUntil(timeout: 20) { self.app.state == .notRunning })
                app = configuredApplication(sessionID: sessionID, appearance: .dark, openNote: nil)
                app.launch()
                main = app.windows.firstMatch
                XCTAssertTrue(main.waitForExistence(timeout: 15))
                waitForCurrentDocumentSurface()
                pane = main.descendants(matching: .any)["scholium.pdf.pane"]
            }
            let page = main.textFields["scholium.pdf.page"]
            XCTAssertTrue(page.waitForExistence(timeout: 10))
            for (title, selected) in [("Select", "select"), ("Highlight", "highlight"), ("Comment", "comment")] {
                chooseReaderMenuItem(title, menu: "PDF Actions", in: pane)
                page.click()
                for tool in ["select", "highlight", "comment"] {
                    let button = pane.descendants(matching: .any)["scholium.pdf.tool." + tool]
                    XCTAssertTrue(button.isEnabled)
                    XCTAssertEqual((button.value as? NSNumber)?.intValue, tool == selected ? 1 : 0)
                }
                attachReaderScreenshot("PDF native foreground — \(dark ? "dark" : "light"), \(title) selected with pointer outside tools", window: main)
            }
            chooseReaderMenuItem("Select", menu: "PDF Actions", in: pane)
            pdfToolbarButton("Note Actions", in: main).click()
            app.menuItems["Note Info…"].firstMatch.click()
            let info = app.windows["scholium.noteInfo"]
            XCTAssertTrue(info.waitForExistence(timeout: 5))
            let summary = info.textFields["scholium.noteInfo.summary"]
            summary.click()
            XCTAssertTrue(NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: summary))
            attachReaderScreenshot("PDF native foreground — \(dark ? "dark" : "light"), main window while Note Info owns focus", window: main)
            info.buttons["Close"].click()
            XCTAssertTrue(waitUntil(timeout: 5) { !info.exists })
            resizeProofWindow(main, toWidth: 900)
            let divider = main.splitGroups["scholium.documentReadingSplit"].splitters.firstMatch
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            divider.click(forDuration: 0.15, thenDragTo: divider.withOffset(CGVector(dx: 80, dy: 0)))
            XCTAssertGreaterThanOrEqual(pane.frame.width, 279)
            openReaderMenu("PDF Actions")
            let selectedItem = app.menuItems["scholium.pdf.actions.selectTool"]
            XCTAssertTrue(selectedItem.waitForExistence(timeout: 3) && selectedItem.isEnabled)
            attachReaderScreenshot("PDF native foreground — \(dark ? "dark" : "light"), compact native action menu", window: main)
            app.typeKey(.escape, modifierFlags: [])
            resizeProofWindow(main, toWidth: 1380)
            XCTAssertEqual(try source(at: noteURL), boundSource)
            XCTAssertEqual(try Data(contentsOf: managed), original)
            XCTAssertEqual(try Data(contentsOf: originalURL), original)
        }
    }

    /// The real PDF plane continues under native toolbar chrome, while tool
    /// selection, pointer annotation and keyboard commands retain their routes.
    @MainActor
    func testPDFReaderNativeToolbarUnderlapAndSelectedTools() throws {
        let originalURL = testDirectory.appendingPathComponent("Synthetic Toolbar Underlap.pdf")
        try makeSearchableReaderPDF(at: originalURL)
        let original = try Data(contentsOf: originalURL)
        waitForCurrentDocumentSurface()
        app.typeKey("p", modifierFlags: [.control, .command])
        var main = app.windows.firstMatch
        var pane = main.descendants(matching: .any)["scholium.pdf.pane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 5))
        pane.buttons["scholium.pdf.attach"].click()
        app.buttons["scholium.pdf.chooseFile"].click()
        chooseReaderPDFInNativePanel(originalURL)
        XCTAssertTrue(main.textFields["scholium.pdf.page"].waitForExistence(timeout: 15))
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let managed = noteURL.deletingLastPathComponent().appendingPathComponent(try readerPDFBinding(in: source(at: noteURL)))
        for dark in [false, true] {
            if dark {
                app.typeKey("q", modifierFlags: .command)
                XCTAssertTrue(waitUntil(timeout: 20) { self.app.state == .notRunning })
                app = configuredApplication(sessionID: sessionID, appearance: .dark, openNote: nil)
                app.launch()
                main = app.windows.firstMatch
                XCTAssertTrue(main.waitForExistence(timeout: 15))
                waitForCurrentDocumentSurface()
                pane = main.descendants(matching: .any)["scholium.pdf.pane"]
            }
            let page = main.textFields["scholium.pdf.page"]
            XCTAssertTrue(page.waitForExistence(timeout: 10))
            typeCommittedText("1", into: page, in: app)
            page.typeKey(.return, modifierFlags: [])
            chooseReaderMenuItem("Fit PDF", menu: "PDF Zoom", in: pane)
            let paper = pane.scrollViews.firstMatch
            XCTAssertTrue(paper.waitForExistence(timeout: 5))
            let searchButton = main.toolbars.firstMatch.buttons["Search PDF"]
            let viewport = pane.descendants(matching: .any)["PDFReader.View"]
            // NSScrollView's AX frame excludes the top/bottom reserved insets.
            // Actual native scroll/clip geometry is proved by the hosting test.
            XCTAssertLessThan(viewport.frame.minY, searchButton.frame.maxY - 10)
            let title = paper.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Lifecycle Quartz", "Lifecycle Quartz")
            ).firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            let titleTop = title.frame.minY
            paper.scroll(byDeltaX: 0, deltaY: -max(titleTop - searchButton.frame.midY, 20))
            XCTAssertTrue(waitUntil(timeout: 5) { title.frame.minY < searchButton.frame.maxY })
            XCTAssertGreaterThan(title.frame.maxY, viewport.frame.minY, "Scrolled page text remains inside the extended PDF plane.")
            chooseReaderMenuItem("Highlight", menu: "PDF Actions", in: pane)
            let highlight = pane.descendants(matching: .any)["scholium.pdf.tool.highlight"]
            let select = pane.descendants(matching: .any)["scholium.pdf.tool.select"]
            XCTAssertEqual((highlight.value as? NSNumber)?.intValue, 1)
            XCTAssertEqual((select.value as? NSNumber)?.intValue, 0)
            attachReaderScreenshot("PDF under toolbar — \(dark ? "dark" : "light"), native Highlight selected", window: main)
            let retainedTitleY = title.frame.minY
            app.typeKey("p", modifierFlags: [.control, .command])
            XCTAssertTrue(waitUntil(timeout: 5) { !pane.exists })
            app.typeKey("p", modifierFlags: [.control, .command])
            XCTAssertTrue(pane.waitForExistence(timeout: 5))
            XCTAssertTrue(waitUntil(timeout: 5) { abs(title.frame.minY - retainedTitleY) < 2 })
            chooseReaderMenuItem("Comment", menu: "PDF Actions", in: pane)
            XCTAssertEqual((pane.descendants(matching: .any)["scholium.pdf.tool.comment"].value as? NSNumber)?.intValue, 1)
            XCTAssertEqual((highlight.value as? NSNumber)?.intValue, 0)
            searchButton.click()
            let search = app.textFields["scholium.pdf.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 3))
            attachReaderScreenshot("PDF native search — \(dark ? "dark" : "light"), popup over paper with Comment armed", window: main)
            typeCommittedText("Pointer Highlight Marker", into: search, in: app, clickWithinVisibleFrame: true)
            search.typeKey(.return, modifierFlags: [])
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })
            XCTAssertFalse(app.descendants(matching: .any)["scholium.pdf.comment"].exists, "Toolbar clicks cannot dispatch the armed Comment tool into paper.")
            chooseReaderMenuItem("Select", menu: "PDF Actions", in: pane)
            let marker = paper.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Pointer Highlight Marker", "Pointer Highlight Marker")
            ).firstMatch
            XCTAssertTrue(marker.waitForExistence(timeout: 5))
            let oldHeight = marker.frame.height
            chooseReaderMenuItem("Zoom In", menu: "PDF Zoom", in: pane)
            XCTAssertTrue(waitUntil(timeout: 5) { marker.frame.height > oldHeight * 1.1 })
            chooseReaderMenuItem("Fit PDF", menu: "PDF Zoom", in: pane)
            if !dark { exerciseBoundedReaderHighlightDrag(in: pane, managedURL: managed) }
            let divider = main.splitGroups["scholium.documentReadingSplit"].splitters.firstMatch
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let oldWidth = pane.frame.width
            divider.click(forDuration: 0.15, thenDragTo: divider.withOffset(CGVector(dx: -45, dy: 0)))
            XCTAssertTrue(waitUntil(timeout: 5) { pane.frame.width > oldWidth + 20 })
            XCTAssertLessThan(viewport.frame.minY, searchButton.frame.maxY - 10)
            paper.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).click()
            pdfToolbarButton("Note Actions", in: main).hover()
            let tools = pane.descendants(matching: .any)["scholium.pdf.tools"]
            XCTAssertTrue(waitUntil(timeout: 8) { !tools.exists })
            attachReaderScreenshot("PDF under toolbar — \(dark ? "dark" : "light"), quiet tools after resize", window: main)
            page.click()
            XCTAssertTrue(waitUntil(timeout: 5) { tools.exists })
            typeCommittedText("2", into: page, in: app)
            page.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "2" })
            XCTAssertEqual(try Data(contentsOf: originalURL), original)
        }
        XCTAssertTrue(
            savedReaderAnnotations(at: managed).contains {
                $0.value(forAnnotationKey: .subtype) as? String == PDFAnnotationSubtype.highlight.rawValue
            })
        try assertReaderWidgetPreserved(at: managed)
    }

    /// Quiet reading, native tracking and field/draft focus share one visible
    /// tools lifetime without changing the paper's geometry or saved bytes.
    @MainActor
    func testPDFReaderFloatingToolsReadingActivityAndInterruption() throws {
        let originalURL = testDirectory.appendingPathComponent("Synthetic Reading Activity.pdf")
        try makeSearchableReaderPDF(at: originalURL)
        let original = try Data(contentsOf: originalURL)
        let main = app.windows.firstMatch
        waitForCurrentDocumentSurface()
        app.typeKey("p", modifierFlags: [.control, .command])
        let pane = main.descendants(matching: .any)["scholium.pdf.pane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 5))
        pane.buttons["scholium.pdf.attach"].click()
        app.buttons["scholium.pdf.chooseFile"].click()
        chooseReaderPDFInNativePanel(originalURL)
        let page = main.textFields["scholium.pdf.page"]
        XCTAssertTrue(page.waitForExistence(timeout: 15))
        let tools = pane.descendants(matching: .any)["scholium.pdf.tools"]
        let select = pane.descendants(matching: .any)["scholium.pdf.tool.select"]
        let paper = pane.scrollViews.firstMatch
        XCTAssertTrue(paper.waitForExistence(timeout: 5))
        let paperFrame = paper.frame
        let noteActions = pdfToolbarButton("Note Actions", in: main)

        // A paper click gives the PDF native focus; that alone must not pin
        // the tools forever. Moving outside leaves a genuinely quiet reader.
        paper.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).click()
        noteActions.hover()
        XCTAssertTrue(waitUntil(timeout: 8) { !tools.exists })
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                select.exists && NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: select)
            }, "Tab from quiet paper reveals and reaches the native Select control.")
        paper.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).click()
        noteActions.hover()
        XCTAssertTrue(waitUntil(timeout: 8) { !tools.exists })
        XCTAssertEqual(paper.frame, paperFrame, "Idle tools preserve their scroll clearance.")
        XCTAssertTrue(main.toolbars.firstMatch.buttons["Search PDF"].isHittable)
        attachReaderScreenshot("PDF motion — quiet paper with persistent native upper controls", window: main)
        pane.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.25)).hover()
        XCTAssertTrue(select.waitForExistence(timeout: 5) && select.isEnabled)
        select.hover()
        let highlight = pane.descendants(matching: .any)["scholium.pdf.tool.highlight"]
        highlight.click()
        XCTAssertEqual((highlight.value as? NSNumber)?.intValue, 1, "Pointer reveal reaches a working native tool.")
        select.click()
        XCTAssertEqual((select.value as? NSNumber)?.intValue, 1)
        XCTAssertFalse(waitUntil(timeout: 3.3) { !tools.exists }, "Hover retains visible tools past their idle deadline.")

        // The native field editor retains an unsubmitted page draft while
        // focus keeps the tools visible even with the pointer elsewhere.
        typeCommittedText("Unsubmitted page draft", into: page, in: app)
        noteActions.hover()
        XCTAssertFalse(waitUntil(timeout: 3.3) { !tools.exists }, "Focused page input pins the tools.")
        XCTAssertEqual(page.value as? String, "Unsubmitted page draft")
        page.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "1" })

        pane.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.25)).hover()
        openReaderMenu("PDF Zoom")
        noteActions.hover()
        XCTAssertFalse(waitUntil(timeout: 3.3) { !tools.exists }, "Native menu tracking pins tools, including outside hover.")
        app.typeKey(.escape, modifierFlags: [])
        chooseReaderMenuItem("Add PDF Comment…", menu: "PDF Actions", in: pane)
        let draft = readerCommentEditor()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        typeCommittedText("Unapplied activity draft 阅读", into: draft, in: app)
        noteActions.hover()
        XCTAssertFalse(waitUntil(timeout: 3.3) { !tools.exists }, "An annotation draft pins the controls.")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !draft.exists })

        // Repeated native command toggles cancel old idle work and reconnect
        // only to the current pane, rather than letting a late hide win.
        for _ in 0..<3 {
            app.typeKey("p", modifierFlags: [.control, .command])
            XCTAssertTrue(waitUntil(timeout: 5) { !pane.exists })
            app.typeKey("p", modifierFlags: [.control, .command])
            XCTAssertTrue(pane.waitForExistence(timeout: 5))
            pane.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.25)).hover()
            XCTAssertTrue(select.waitForExistence(timeout: 5) && select.isEnabled)
            select.hover()
        }
        noteActions.hover()
        XCTAssertTrue(waitUntil(timeout: 8) { !tools.exists })
        page.click()
        XCTAssertTrue(waitUntil(timeout: 5) { tools.exists }, "Keyboard focus reveals controls after quiet reading.")
        XCTAssertEqual(page.value as? String, "1")
        XCTAssertEqual(paper.frame, paperFrame)
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let managed = noteURL.deletingLastPathComponent().appendingPathComponent(try readerPDFBinding(in: source(at: noteURL)))
        XCTAssertEqual(try Data(contentsOf: managed), original, "Presentation creates no annotation or PDF write.")
        XCTAssertEqual(try Data(contentsOf: originalURL), original)
        attachReaderScreenshot("PDF motion — focus reveal after interrupted repeated toggles", window: main)

        // The pane follows the selected Note equally in each Triptych slot.
        // Cancelling a chooser on an empty peer Note changes neither its
        // source nor the first Note's reading session/binding.
        let navigator = main.descendants(matching: .any)["scholium.workspaceNavigator"]
        for (slot, directory, title) in [("Topics", "02-topics", "QA Topic"), ("Works", "03-works", "QA Work")] {
            let peerURL = triptychDirectory.appendingPathComponent("\(directory)/\(title).md")
            let peerBytes = try Data(contentsOf: peerURL)
            navigator.descendants(matching: .any)[slot].firstMatch.click()
            XCTAssertTrue(main.descendants(matching: .any)["scholium.noteRow.\(title).md"].waitForExistence(timeout: 8))
            openNote(title + ".md", expectedTitle: title, in: main)
            XCTAssertTrue(pane.buttons["scholium.pdf.attach"].waitForExistence(timeout: 8))
            XCTAssertFalse(page.exists)
            pane.buttons["scholium.pdf.attach"].click()
            XCTAssertTrue(app.buttons["scholium.pdf.chooseFile"].waitForExistence(timeout: 3))
            main.sheets.firstMatch.buttons["Cancel"].click()
            XCTAssertTrue(waitUntil(timeout: 5) { !self.app.buttons["scholium.pdf.chooseFile"].exists })
            XCTAssertEqual(try Data(contentsOf: peerURL), peerBytes)
        }
        navigator.descendants(matching: .any)["Analyses"].firstMatch.click()
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: main)
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        XCTAssertEqual(page.value as? String, "1")
        XCTAssertEqual(try Data(contentsOf: managed), original)
        attachReaderScreenshot("PDF motion — restored bound Note after all three Triptych slots", window: main)
    }

    /// Long native form fields and a dirty footer remain usable in the compact
    /// panel's two localizations, while closing never changes Markdown.
    @MainActor
    func testNoteInfoCompactLongFieldsAndDraftFooter() throws {
        let title = "Synthetic Compact Note Information Reading Lifecycle and Long Fields 研究笔记信息完整保真"
        let relativeDirectory = String(repeating: "Long synthetic research directory 研究/", count: 5)
        let directory = triptychDirectory.appendingPathComponent(
            "01-analyses/" + relativeDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let noteURL = directory.appendingPathComponent(title + ".md")
        let summary = String(repeating: "Long authored summary with Unicode 阅读摘要 👩‍🔬 e\u{301}. ", count: 22)
        let tags = (1...18).map { "synthetic-research-tag-\($0)-研究" }
        let sourceText =
            "---\nsummary: '\(summary)'\ntags: [\(tags.map { "'\($0)'" }.joined(separator: ", "))]\n"
            + "unknown: 'preserved' # exact\n---\n\n# \(title)\n\nSynthetic body remains unchanged.\n"
        try sourceText.write(to: noteURL, atomically: true, encoding: .utf8)
        let original = try Data(contentsOf: noteURL)
        for chinese in [false, true] {
            app.terminate()
            sessionID = UUID()
            app = configuredApplication(
                sessionID: sessionID, appearance: chinese ? .dark : .light, openNote: relativeDirectory + title + ".md"
            )
            if chinese { app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] }
            app.launch()
            let main = app.windows.firstMatch
            XCTAssertTrue(main.waitForExistence(timeout: 15))
            XCTAssertTrue(waitForDocumentTitle(title, in: main, timeout: 20))
            pdfToolbarButton(chinese ? "笔记操作" : "Note Actions", in: main).click()
            let action = app.menuItems[chinese ? "笔记信息…" : "Note Info…"].firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 3))
            action.click()
            let info = app.windows["scholium.noteInfo"]
            XCTAssertTrue(info.waitForExistence(timeout: 5))
            XCTAssertEqual(info.frame.width, 360, accuracy: 3)
            let displayedTitle = info.staticTexts["scholium.noteInfo.title"]
            XCTAssertEqual((displayedTitle.value as? String) ?? displayedTitle.label, title)
            let field = info.textFields["scholium.noteInfo.summary"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            XCTAssertEqual(field.value as? String, summary)
            let tagField = info.textFields["scholium.noteInfo.tags"]
            XCTAssertEqual(tagField.value as? String, tags.joined(separator: "\n"))
            XCTAssertGreaterThan(field.frame.width, info.frame.width * 0.7, "Long values use the compact panel's available width.")
            XCTAssertGreaterThan(tagField.frame.width, info.frame.width * 0.7)
            let whereText = info.staticTexts["scholium.noteInfo.location"]
            XCTAssertEqual((whereText.value as? String) ?? whereText.label, noteURL.path)
            let draft = summary + "\nUnapplied final paragraph 未应用末尾。"
            typeCommittedText(draft, into: field, in: app)
            XCTAssertEqual(try Data(contentsOf: noteURL), original)
            resizeProofWindow(info, toWidth: 340, height: 400)
            XCTAssertGreaterThan(field.frame.width, info.frame.width * 0.7)
            let reload = info.buttons[chinese ? "重新载入" : "Reload"]
            let discard = info.buttons[chinese ? "放弃更改" : "Discard Changes"]
            let apply = info.buttons["scholium.noteInfo.apply"]
            let close = info.buttons[chinese ? "关闭" : "Close"]
            for button in [reload, discard, apply, close] {
                XCTAssertTrue(button.exists && button.isHittable, "Compact dirty footer keeps every action visible.")
                XCTAssertTrue(info.frame.contains(button.frame), "Footer buttons remain inside the native panel.")
            }
            XCTAssertFalse(reload.isEnabled)
            XCTAssertTrue(discard.isEnabled && apply.isEnabled && close.isEnabled)
            attachReaderScreenshot("Note Info — compact long values and dirty footer, \(chinese ? "Chinese dark" : "English light")", window: info)
            close.click()
            let keep = info.sheets.firstMatch.buttons[chinese ? "继续编辑" : "Keep Editing"]
            XCTAssertTrue(keep.waitForExistence(timeout: 3))
            keep.click()
            XCTAssertTrue(info.exists)
            XCTAssertEqual(field.value as? String, draft)
            discard.click()
            XCTAssertTrue(waitUntil(timeout: 5) { field.value as? String == summary })
            close.click()
            XCTAssertTrue(waitUntil(timeout: 5) { !info.exists })
            XCTAssertEqual(try Data(contentsOf: noteURL), original)
        }
    }

    /// Page input, search keyboard/button dispatch and cancellation are one
    /// native control boundary, independent of annotation save persistence.
    @MainActor
    func testPDFReaderSearchAndPageControlStates() throws {
        let originalURL = testDirectory.appendingPathComponent("Synthetic Search Controls.pdf")
        try makeSearchableReaderPDF(at: originalURL)
        let original = try Data(contentsOf: originalURL)
        let main = app.windows.firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
        app.typeKey("p", modifierFlags: [.control, .command])
        let pane = main.descendants(matching: .any)["scholium.pdf.pane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 5))
        openReaderMenu("PDF Actions")
        for title in ["Show Annotations", "Reload PDF", "Export PDF…", "Detach PDF"] {
            XCTAssertFalse(app.menuItems[title].firstMatch.isEnabled, "\(title) needs a PDF or an authored binding.")
        }
        app.typeKey(.escape, modifierFlags: [])
        pane.buttons["scholium.pdf.attach"].click()
        app.buttons["scholium.pdf.chooseFile"].click()
        chooseReaderPDFInNativePanel(originalURL)
        let page = main.textFields["scholium.pdf.page"]
        XCTAssertTrue(page.waitForExistence(timeout: 15))
        typeCommittedText("1", into: page, in: app)
        page.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "1" })
        XCTAssertFalse(main.buttons["Previous PDF Page"].isEnabled)
        XCTAssertTrue(main.buttons["Next PDF Page"].isEnabled)
        main.buttons["Next PDF Page"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "2" })
        XCTAssertFalse(main.buttons["Next PDF Page"].isEnabled)
        for invalid in ["0", "-1", String(Int.min), String(Int.max), "3", "abc", "999999999999999999999"] {
            typeCommittedText(invalid, into: page, in: app)
            page.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "2" }, "Invalid page \(invalid) preserves the current page.")
        }
        typeCommittedText(" 1 ", into: page, in: app)
        page.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "1" })
        for (label, tool) in [("Highlight", "highlight"), ("Comment", "comment"), ("Select", "select")] {
            openReaderMenu("PDF Actions")
            let command = app.menuItems["scholium.pdf.actions." + tool + "Tool"]
            XCTAssertTrue(command.exists && command.isEnabled, "\(label) must dispatch through the PDF menu owner.")
            command.click()
            let selected = pane.descendants(matching: .any)["scholium.pdf.tool." + tool]
            XCTAssertEqual((selected.value as? NSNumber)?.intValue, 1)
            selected.click()
            XCTAssertEqual((selected.value as? NSNumber)?.intValue, 1, "Repeated tool clicks retain one selected tool.")
        }
        for _ in 0..<3 { chooseReaderMenuItem("Zoom In", menu: "PDF Zoom", in: pane) }

        main.toolbars.firstMatch.buttons["Search PDF"].click()
        let search = app.textFields["scholium.pdf.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        let previous = app.buttons["Previous PDF Match"]
        let next = app.buttons["Next PDF Match"]
        XCTAssertFalse(previous.isEnabled, "An empty PDF query has no previous match.")
        XCTAssertFalse(next.isEnabled, "An empty PDF query has no next match.")
        typeCommittedText("__MissingPDFControlPassage__", into: search, in: app, clickWithinVisibleFrame: true)
        next.click()
        let noMatch = app.staticTexts["No matches in this PDF."]
        XCTAssertTrue(noMatch.waitForExistence(timeout: 3))
        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(search.value as? String, "")
        XCTAssertTrue(waitUntil(timeout: 3) { !noMatch.exists && !previous.isEnabled && !next.isEnabled })
        typeCommittedText("Scholium PDF Lifecycle", into: search, in: app, clickWithinVisibleFrame: true)
        XCTAssertTrue(previous.isEnabled && next.isEnabled)
        search.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "1" })
        next.click()
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "2" })
        previous.click()
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "1" })
        search.click()
        search.typeKey(.return, modifierFlags: .shift)
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "2" }, "Shift-Return searches backward and wraps.")
        search.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "1" }, "Return searches forward and wraps.")
        attachReaderScreenshot("PDF controls — page bounds and forward/backward search", window: main)
        search.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })
        main.toolbars.firstMatch.buttons["Search PDF"].click()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "Scholium PDF Lifecycle")
        search.typeKey(.escape, modifierFlags: [])
        chooseReaderMenuItem("Fit PDF", menu: "PDF Zoom", in: pane)
        main.buttons["Next PDF Page"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "2" })
        main.buttons["Previous PDF Page"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "1" })
        XCTAssertEqual(try Data(contentsOf: originalURL), original)
    }

    /// Reading a long annotation remains a complete task when the PDF denies
    /// mutations. Zotero picker cancellation is exercised without API reads.
    @MainActor
    func testPDFReaderReadOnlyLongCommentAndChooserCancellation() throws {
        let originalURL = testDirectory.appendingPathComponent("Synthetic Read Only.pdf")
        try makeSearchableReaderPDF(at: originalURL)
        let document = try XCTUnwrap(PDFDocument(url: originalURL))
        let fullComment = (0..<90).map { "Paragraph \($0 + 1): complete synthetic read-only comment 阅读批注。" }.joined(separator: "\n")
        let annotation = PDFAnnotation(bounds: CGRect(x: 90, y: 480, width: 24, height: 24), forType: .text, withProperties: nil)
        annotation.contents = fullComment
        try XCTUnwrap(document.page(at: 0)).addAnnotation(annotation)
        let permissions = PDFAccessPermissions.allowsContentCopying.rawValue | PDFAccessPermissions.allowsContentAccessibility.rawValue
        let encrypted = try XCTUnwrap(
            document.dataRepresentation(options: [
                PDFDocumentWriteOption.ownerPasswordOption: "SyntheticOwnerOnly", PDFDocumentWriteOption.accessPermissionsOption: NSNumber(value: permissions),
            ]))
        try encrypted.write(to: originalURL)
        let checked = try XCTUnwrap(PDFDocument(data: encrypted))
        XCTAssertFalse(checked.isLocked)
        XCTAssertFalse(checked.allowsCommenting)
        let main = app.windows.firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
        app.typeKey("p", modifierFlags: [.control, .command])
        let pane = main.descendants(matching: .any)["scholium.pdf.pane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 5))
        pane.buttons["scholium.pdf.attach"].click()
        app.buttons["scholium.pdf.chooseFile"].click()
        chooseReaderPDFInNativePanel(originalURL)
        XCTAssertTrue(main.textFields["scholium.pdf.page"].waitForExistence(timeout: 15))
        pane.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.25)).hover()
        XCTAssertTrue(pane.staticTexts["This PDF permits reading only."].exists)
        for tool in ["highlight", "comment"] {
            XCTAssertFalse(pane.descendants(matching: .any)["scholium.pdf.tool." + tool].isEnabled)
        }
        let select = pane.descendants(matching: .any)["scholium.pdf.tool.select"]
        XCTAssertTrue(select.isEnabled)
        select.click()
        XCTAssertEqual((select.value as? NSNumber)?.intValue, 1)
        chooseReaderMenuItem("Show Annotations", menu: "PDF Actions", in: pane)
        let row = pane.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Paragraph 1:")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        let detail = app.descendants(matching: .any)["scholium.pdf.annotation.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let contents = detail.staticTexts["scholium.pdf.annotation.contents"]
        XCTAssertEqual((contents.value as? String) ?? contents.label, fullComment)
        XCTAssertFalse(detail.buttons["scholium.pdf.annotation.edit"].isEnabled)
        let scroll = detail.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists)
        let initialFrame = contents.frame
        scroll.scroll(byDeltaX: 0, deltaY: -2400)
        XCTAssertTrue(waitUntil(timeout: 5) { contents.frame.minY < initialFrame.minY - 100 })
        attachReaderScreenshot("PDF controls — long read-only annotation scrolled, editing unavailable", window: main)
        detail.buttons["scholium.pdf.annotation.close"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !detail.exists })

        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let sourceBefore = try source(at: noteURL)
        chooseReaderMenuItem("Attach or Replace PDF…", menu: "PDF Actions", in: pane)
        let zotero = app.buttons["Import from Zotero…"]
        XCTAssertTrue(zotero.waitForExistence(timeout: 5))
        zotero.click()
        let query = app.textFields["scholium.pdf.zotero.search"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        let search = app.buttons["Search"].firstMatch
        XCTAssertFalse(search.isEnabled)
        typeCommittedText(String(repeating: "阅", count: 171), into: query, in: app)
        XCTAssertTrue(app.staticTexts["scholium.pdf.zotero.search.validation"].waitForExistence(timeout: 3))
        XCTAssertFalse(search.isEnabled)
        main.sheets.firstMatch.buttons["Back"].click()
        XCTAssertTrue(app.buttons["scholium.pdf.chooseFile"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !self.app.buttons["scholium.pdf.chooseFile"].exists })
        XCTAssertEqual(try source(at: noteURL), sourceBefore)
        XCTAssertEqual(try Data(contentsOf: originalURL), encrypted)
    }

    /// Duplicate identity, checked conflict and native export/reload controls
    /// share one attachment lifetime and preserve every imported original.
    @MainActor
    func testPDFReaderDuplicateChooserAndConflictRecoveryControls() throws {
        let firstURL = testDirectory.appendingPathComponent("original-one/Material.pdf")
        let secondURL = testDirectory.appendingPathComponent("original-two/Material.pdf")
        for url in [firstURL, secondURL] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try makeSearchableReaderPDF(at: url)
        }
        let secondDocument = try XCTUnwrap(PDFDocument(url: secondURL))
        let secondMarker = PDFAnnotation(bounds: CGRect(x: 110, y: 440, width: 24, height: 24), forType: .text, withProperties: nil)
        secondMarker.contents = "Distinct second original"
        try XCTUnwrap(secondDocument.page(at: 0)).addAnnotation(secondMarker)
        XCTAssertTrue(secondDocument.write(to: secondURL))
        let firstBytes = try Data(contentsOf: firstURL)
        let secondBytes = try Data(contentsOf: secondURL)
        let main = app.windows.firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
        app.typeKey("p", modifierFlags: [.control, .command])
        let pane = main.descendants(matching: .any)["scholium.pdf.pane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 5))
        pane.buttons["scholium.pdf.attach"].click()
        app.buttons["scholium.pdf.chooseFile"].click()
        chooseReaderPDFInNativePanel(firstURL)
        XCTAssertTrue(main.textFields["scholium.pdf.page"].waitForExistence(timeout: 15))
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let firstBinding = try readerPDFBinding(in: source(at: noteURL))
        let firstManaged = noteURL.deletingLastPathComponent().appendingPathComponent(firstBinding).standardizedFileURL
        chooseReaderMenuItem("Attach or Replace PDF…", menu: "PDF Actions", in: pane)
        app.buttons["scholium.pdf.chooseFile"].click()
        chooseReaderPDFInNativePanel(secondURL)
        XCTAssertTrue(waitUntil(timeout: 15) { main.textFields["scholium.pdf.page"].exists && !self.app.buttons["scholium.pdf.chooseFile"].exists })
        let secondBinding = try readerPDFBinding(in: source(at: noteURL))
        XCTAssertNotEqual(firstBinding, secondBinding)
        chooseReaderMenuItem("Attach or Replace PDF…", menu: "PDF Actions", in: pane)
        let choices = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "scholium.pdf.shared."))
        XCTAssertTrue(waitUntil(timeout: 5) { choices.count >= 2 })
        let labels = choices.allElementsBoundByIndex.map { ($0.value as? String) ?? $0.label }
        XCTAssertTrue(labels.contains { $0.contains("Copy 1") } && labels.contains { $0.contains("Copy 2") })
        let firstID = firstManaged.deletingLastPathComponent().lastPathComponent.lowercased()
        let firstChoice = app.descendants(matching: .any)["scholium.pdf.shared." + firstID]
        XCTAssertTrue(firstChoice.isHittable)
        firstChoice.click()
        app.buttons["scholium.pdf.details"].click()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", firstID, firstID)).firstMatch
                .waitForExistence(timeout: 3))
        let closeDetails = app.buttons["scholium.pdf.details.close"]
        XCTAssertTrue(closeDetails.waitForExistence(timeout: 3))
        closeDetails.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !closeDetails.exists && self.app.buttons["Attach Selected PDF"].exists })
        app.buttons["scholium.pdf.details"].click()
        XCTAssertTrue(closeDetails.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["Attach Selected PDF"].waitForExistence(timeout: 3), "Closing PDF Details keeps the attachment chooser open.")
        app.buttons["Attach Selected PDF"].click()
        XCTAssertTrue(waitUntil(timeout: 10) { (try? self.readerPDFBinding(in: self.source(at: noteURL))) == firstBinding })

        chooseReaderMenuItem("Add PDF Comment…", menu: "PDF Actions", in: pane)
        let localComment = "Retained local candidate after external PDF change"
        typeCommittedText(localComment, into: readerCommentEditor(), in: app)
        let external = try XCTUnwrap(PDFDocument(url: firstManaged))
        let peerComment = PDFAnnotation(bounds: CGRect(x: 100, y: 460, width: 24, height: 24), forType: .text, withProperties: nil)
        peerComment.contents = "External winning annotations"
        try XCTUnwrap(external.page(at: 1)).addAnnotation(peerComment)
        XCTAssertTrue(external.write(to: firstManaged))
        let winningBytes = try Data(contentsOf: firstManaged)
        app.buttons["scholium.pdf.comment.save"].click()
        let error = pane.staticTexts["scholium.pdf.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        pane.buttons["Retry Save"].click()
        XCTAssertTrue(waitUntil(timeout: 10) { pane.buttons["Retry Save"].isEnabled })
        XCTAssertEqual(try Data(contentsOf: firstManaged), winningBytes)
        XCTAssertFalse(pane.buttons["Reload PDF…"].exists)
        openReaderMenu("PDF Actions")
        XCTAssertFalse(app.menuItems["scholium.pdf.actions.reload"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        pane.buttons["Export Annotations…"].click()
        chooseReaderExportDestination(testDirectory.appendingPathComponent("Retained Control Candidate.pdf"))
        let exported = testDirectory.appendingPathComponent("Retained Control Candidate.pdf")
        XCTAssertTrue(waitUntil(timeout: 10) { FileManager.default.fileExists(atPath: exported.path) && pane.buttons["Reload PDF…"].exists })
        XCTAssertTrue(savedReaderAnnotations(at: exported).contains { $0.contents == localComment })
        XCTAssertFalse(savedReaderAnnotations(at: exported).contains { $0.contents == peerComment.contents })
        openReaderMenu("PDF Actions")
        XCTAssertFalse(app.menuItems["scholium.pdf.actions.reload"].isEnabled, "Discarding retained annotations requires the recovery confirmation.")
        app.typeKey(.escape, modifierFlags: [])
        let candidate = XCTAttachment(data: try Data(contentsOf: exported), uniformTypeIdentifier: "com.adobe.pdf")
        candidate.name = "Retained annotations exported without replacing external PDF"
        candidate.lifetime = .keepAlways
        add(candidate)
        pane.buttons["Reload PDF…"].click()
        let confirmation = main.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Cancel"].click()
        XCTAssertTrue(error.exists)
        pane.buttons["Reload PDF…"].click()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Reload PDF"].click()
        XCTAssertTrue(waitUntil(timeout: 10) { !error.exists && main.textFields["scholium.pdf.page"].exists })
        XCTAssertEqual(try Data(contentsOf: firstManaged), winningBytes)
        chooseReaderMenuItem("Detach PDF", menu: "PDF Actions", in: pane)
        XCTAssertTrue(pane.buttons["scholium.pdf.attach"].waitForExistence(timeout: 10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstManaged.path))
        XCTAssertEqual(try Data(contentsOf: firstManaged), winningBytes)
        XCTAssertEqual(try Data(contentsOf: firstURL), firstBytes)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondBytes)
        attachReaderScreenshot("PDF controls — checked export/reload and detach preserves shared copies", window: main)
    }

    /// A distinct narrow-layout boundary: visible AX names, keyboard focus and
    /// navigation, native menu keyboard dispatch, and PDF zoom without changing
    /// the user's display or accessibility settings.
    @MainActor
    func testPDFReaderKeyboardLabelsZoomAndNarrowNavigation() throws {
        let originalURL = testDirectory.appendingPathComponent("Synthetic Keyboard Reader.pdf")
        try makeSearchableReaderPDF(at: originalURL)
        let original = try Data(contentsOf: originalURL)
        let main = app.windows.firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
        app.typeKey("p", modifierFlags: [.control, .command])
        let pane = main.descendants(matching: .any)["scholium.pdf.pane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 5))
        let emptyActions = pdfToolbarButton("PDF Actions", in: main)
        XCTAssertTrue(emptyActions.waitForExistence(timeout: 5) && emptyActions.isHittable)
        let noteActions = pdfToolbarButton("Note Actions", in: main)
        XCTAssertEqual(emptyActions.frame.height, noteActions.frame.height, accuracy: 4)
        XCTAssertEqual(emptyActions.frame.width, noteActions.frame.width, accuracy: 10)
        XCTAssertTrue(waitUntil(timeout: 5) { abs(noteActions.frame.maxX - pane.frame.minX) <= 10 })
        attachReaderScreenshot("PDF Reader — empty pane, native More and aligned document actions", window: main)
        pane.buttons["scholium.pdf.attach"].click()
        let chooseFile = app.buttons["scholium.pdf.chooseFile"]
        XCTAssertTrue(chooseFile.waitForExistence(timeout: 5))
        chooseFile.click()
        chooseReaderPDFInNativePanel(originalURL)
        let page = main.textFields["scholium.pdf.page"]
        XCTAssertTrue(page.waitForExistence(timeout: 15))
        resizeProofWindow(main, toWidth: 900)
        let divider = main.splitGroups["scholium.documentReadingSplit"].splitters.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        divider.click(forDuration: 0.15, thenDragTo: divider.withOffset(CGVector(dx: pane.frame.width - 280, dy: 0)))
        XCTAssertTrue(waitUntil(timeout: 5) { pane.frame.width >= 279 && pane.frame.width <= 300 })
        XCTAssertTrue(waitUntil(timeout: 5) { abs(noteActions.frame.maxX - pane.frame.minX) <= 10 })
        XCTAssertEqual(page.label, "PDF Page")
        let compact = pdfToolbarButton("PDF Reader", in: main)
        XCTAssertTrue(waitUntil(timeout: 5) { compact.isHittable })
        XCTAssertEqual(compact.label, "PDF Reader")
        XCTAssertGreaterThanOrEqual(page.frame.minX, pane.frame.minX - 2)
        XCTAssertGreaterThanOrEqual(compact.frame.minX, pane.frame.minX - 2)
        let more = pdfToolbarButton("Note Actions", in: main)
        XCTAssertLessThanOrEqual(more.frame.maxX, pane.frame.minX + 2)
        typeCommittedText("2", into: page, in: app)
        page.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "2" })
        // AppKit owns toolbar focus traversal under the user's Keyboard
        // Navigation settings. This journey verifies native menu keyboard
        // selection and dispatch after opening the standard menu button.
        compact.click()
        XCTAssertTrue(app.menuItems["Search PDF"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Previous PDF Page"].firstMatch.isEnabled)
        XCTAssertFalse(app.menuItems["Next PDF Page"].firstMatch.isEnabled)
        for label in ["PDF Actions"] {
            XCTAssertTrue(app.menuItems[label].firstMatch.exists)
        }
        app.typeKey("s", modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        let search = app.textFields["scholium.pdf.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(search.label, "Search PDF")
        for label in ["Previous PDF Match", "Next PDF Match"] {
            XCTAssertTrue(app.buttons[label].isHittable)
        }
        typeCommittedText("NoSuchPDFPassage synthetic __", into: search, in: app, clickWithinVisibleFrame: true)
        search.typeKey(.return, modifierFlags: [])
        let noMatch = app.staticTexts["No matches in this PDF."]
        XCTAssertTrue(noMatch.waitForExistence(timeout: 3), "Return submits the PDF search.")
        typeCommittedText("Lifecycle Quartz", into: search, in: app, clickWithinVisibleFrame: true)
        search.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !noMatch.exists })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })

        let nativePDF = pane.scrollViews.firstMatch
        // Continuous PDFKit reports the page at the viewport midpoint. At
        // minimum width it can show both pages while revealing the first match.
        let matchedPassage = nativePDF.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Lifecycle Quartz", "Lifecycle Quartz")
        ).firstMatch
        XCTAssertTrue(matchedPassage.waitForExistence(timeout: 3))
        XCTAssertTrue(matchedPassage.isHittable)
        XCTAssertTrue(nativePDF.frame.intersects(matchedPassage.frame))
        attachReaderScreenshot("PDF Reader — narrow keyboard search reveals first-page match", window: main)
        let marker = nativePDF.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Pointer Highlight Marker", "Pointer Highlight Marker")
        ).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        let baselineTextHeight = marker.frame.height
        openReaderMenu("PDF Zoom")
        XCTAssertTrue(app.menuItems["Zoom In"].firstMatch.waitForExistence(timeout: 3))
        // Enter the native submenu before type-selection and Return.
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey("z", modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { marker.frame.height > baselineTextHeight * 1.1 })
        chooseReaderMenuItem("Zoom Out", menu: "PDF Zoom", in: pane)
        XCTAssertTrue(waitUntil(timeout: 5) { abs(marker.frame.height - baselineTextHeight) < 3 })
        chooseReaderMenuItem("Fit PDF", menu: "PDF Zoom", in: pane)
        typeCommittedText("2", into: page, in: app)
        page.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "2" })
        chooseReaderMenuItem("Fit PDF", menu: "PDF Zoom", in: pane)
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "2" })
        attachReaderScreenshot("PDF Reader — minimum pane, labels and keyboard navigation", window: main)
        resizeProofWindow(main, toWidth: 1400)
        let widerDivider = main.splitGroups["scholium.documentReadingSplit"].splitters.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        widerDivider.click(forDuration: 0.15, thenDragTo: widerDivider.withOffset(CGVector(dx: -300, dy: 0)))
        let fullSearch = main.toolbars.firstMatch.buttons["Search PDF"]
        XCTAssertTrue(waitUntil(timeout: 5) { fullSearch.isHittable && !compact.isHittable })
        XCTAssertGreaterThanOrEqual(page.frame.minX, pane.frame.minX - 2)
        XCTAssertLessThanOrEqual(more.frame.maxX, pane.frame.minX + 2)
        attachReaderScreenshot("PDF Reader — wide native controls restored within reader region", window: main)
        typeCommittedText("2", into: page, in: app)
        page.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "2" })
        let beforeCloseActionsX = more.frame.maxX
        let closingReaderWidth = pane.frame.width
        app.typeKey("p", modifierFlags: [.control, .command])
        XCTAssertTrue(waitUntil(timeout: 5) { !page.exists })
        XCTAssertTrue(
            waitUntil(timeout: 5) { more.frame.maxX > beforeCloseActionsX + closingReaderWidth - 120 },
            "Document actions follow the expanded Markdown region when PDF closes.")
        app.typeKey("p", modifierFlags: [.control, .command])
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { abs(more.frame.maxX - pane.frame.minX) <= 10 })
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "2" })
        XCTAssertEqual(try Data(contentsOf: originalURL), original)
    }

    /// One native journey owns the boundary from authored note binding through
    /// persisted PDF annotations and a restored reader. All files are in this
    /// test's disposable Triptych copy; the synthetic import stays untouched.
    @MainActor
    func testPDFReaderNoteBindingAnnotationsAndRestoration() throws {
        let originalURL = testDirectory.appendingPathComponent("Synthetic Reader.pdf")
        try makeSearchableReaderPDF(at: originalURL)
        let originalBytes = try Data(contentsOf: originalURL)
        let fixture = try XCTUnwrap(PDFDocument(data: originalBytes))
        XCTAssertEqual(fixture.pageCount, 2)
        XCTAssertEqual(fixture.findString("Lifecycle Quartz", withOptions: []).count, 1)
        try assertReaderWidgetPreserved(at: originalURL)
        let originalEvidence = XCTAttachment(data: originalBytes, uniformTypeIdentifier: "com.adobe.pdf")
        originalEvidence.name = "Unmodified synthetic source PDF"
        originalEvidence.lifetime = .keepAlways
        add(originalEvidence)

        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let initialSource = try source(at: noteURL)
        var main = app.windows.firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
        let showReader = pdfToolbarButton("Show PDF Reader", in: main)
        XCTAssertTrue(showReader.waitForExistence(timeout: 5))
        XCTAssertTrue(showReader.isEnabled)
        showReader.click()
        var pane = main.descendants(matching: .any)["scholium.pdf.pane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 5))
        pane.buttons["scholium.pdf.attach"].click()
        let chooseFile = app.buttons["scholium.pdf.chooseFile"]
        XCTAssertTrue(chooseFile.waitForExistence(timeout: 5))

        // Cancellation must return to the chooser without authoring a binding.
        chooseFile.click()
        let cancelledPanel = app.descendants(matching: .any)["open-panel"]
        XCTAssertTrue(cancelledPanel.waitForExistence(timeout: 5))
        cancelledPanel.buttons["CancelButton"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !cancelledPanel.exists })
        XCTAssertEqual(try source(at: noteURL), initialSource)
        XCTAssertTrue(chooseFile.isEnabled)
        chooseFile.click()
        chooseReaderPDFInNativePanel(originalURL)

        XCTAssertTrue(
            waitUntil(timeout: 15) {
                main.textFields["scholium.pdf.page"].exists
                    && !self.app.buttons["scholium.pdf.chooseFile"].exists
            })
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                (try? self.readerPDFBinding(in: self.source(at: noteURL))) != nil
            })
        let boundSource = try source(at: noteURL)
        let binding = try readerPDFBinding(in: boundSource)
        let managedURL = noteURL.deletingLastPathComponent().appendingPathComponent(binding).standardizedFileURL
        let filesRoot = triptychDirectory.appendingPathComponent(".scholium/attachments/files").path + "/"
        XCTAssertTrue(managedURL.path.hasPrefix(filesRoot), "Binding \(binding) resolved to \(managedURL.path), outside \(filesRoot)")
        XCTAssertNotEqual(managedURL, originalURL)
        XCTAssertEqual(try Data(contentsOf: managedURL), originalBytes)
        XCTAssertEqual(try sourceWithoutPDFBinding(boundSource), initialSource)
        let nativePDF = pane.scrollViews.firstMatch
        XCTAssertTrue(nativePDF.waitForExistence(timeout: 5))
        pane.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.25)).hover()
        let tools = pane.descendants(matching: .any)["scholium.pdf.tools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.hover()
        XCTAssertEqual(tools.frame.midX, pane.frame.midX, accuracy: 3)
        XCTAssertLessThan(tools.frame.width, pane.frame.width)
        XCTAssertGreaterThan(tools.frame.minY, pane.frame.midY)
        for (tool, label) in [("select", "Select"), ("highlight", "Highlight"), ("comment", "Comment")] {
            let control = pane.descendants(matching: .any)["scholium.pdf.tool." + tool]
            XCTAssertTrue(control.exists && control.isEnabled)
            XCTAssertEqual(control.label, label)
        }
        XCTAssertFalse(main.toolbars.firstMatch.descendants(matching: .any)["scholium.pdf.zoom"].exists)
        XCTAssertLessThan(nativePDF.frame.minY - pane.frame.minY, 55, "PDF paper starts at the native toolbar edge, without a stacked reader header.")
        XCTAssertEqual(
            pane.frame.maxY - nativePDF.frame.maxY,
            tools.frame.height + pane.frame.maxY - tools.frame.maxY, accuracy: 6,
            "The native scroll extent reserves the floating tools' clearance.")
        let readerToggle = pdfToolbarButton("Hide PDF Reader", in: main)
        XCTAssertEqual((readerToggle.value as? NSNumber)?.intValue, 1)
        resizeProofWindow(main, toWidth: 1380)
        verifyReaderPaneVisibilityMatrix(in: main)
        XCTAssertTrue(pane.waitForExistence(timeout: 5))
        attachReaderScreenshot("PDF Reader — light, full-height paper and pane-relative controls", window: main)
        let formField = nativePDF.textFields.matching(
            NSPredicate(format: "value == %@ OR label == %@", "Synthetic widget value", "SyntheticWidget")
        ).firstMatch
        if formField.exists {
            XCTAssertFalse(formField.isEnabled, "PDF form fields exposed to accessibility must be read-only.")
        }

        // Note Info is a separate More action; cancelling a field draft leaves
        // the exact Markdown and the PDF binding unchanged.
        let noteActions = main.toolbars.firstMatch.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Note Actions")).firstMatch
        XCTAssertTrue(noteActions.waitForExistence(timeout: 5))
        noteActions.click()
        let infoAction = app.menuItems["Note Info…"].firstMatch
        XCTAssertTrue(infoAction.waitForExistence(timeout: 3))
        infoAction.click()
        let info = app.windows["scholium.noteInfo"]
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        let summary = info.textFields["scholium.noteInfo.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        typeCommittedText("Unapplied synthetic metadata", into: summary, in: app)
        info.buttons["Close"].click()
        let discard = info.sheets.firstMatch.buttons["Discard Changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !info.exists })
        XCTAssertEqual(try source(at: noteURL), boundSource)

        main.toolbars.firstMatch.buttons["Search PDF"].click()
        let search = app.textFields["scholium.pdf.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        typeCommittedText("Lifecycle Quartz", into: search, in: app, clickWithinVisibleFrame: true)
        search.typeKey(.return, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })
        chooseReaderMenuItem("Highlight Selection", menu: "PDF Actions", in: pane)
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                self.savedReaderAnnotations(at: managedURL).contains {
                    $0.value(forAnnotationKey: .subtype) as? String == PDFAnnotationSubtype.highlight.rawValue
                }
            }, "The native selection highlight must be saved in the managed copy.")
        exerciseBoundedReaderHighlightDrag(in: pane, managedURL: managedURL)

        let firstComment = "Synthetic lifecycle comment"
        chooseReaderMenuItem("Add PDF Comment…", menu: "PDF Actions", in: pane)
        let comment = readerCommentEditor()
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        typeCommittedText(firstComment, into: comment, in: app)
        app.buttons["scholium.pdf.comment.save"].click()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                self.savedReaderAnnotations(at: managedURL).contains {
                    $0.value(forAnnotationKey: .subtype) as? String == PDFAnnotationSubtype.text.rawValue && $0.contents == firstComment
                }
            })
        XCTAssertEqual(try Data(contentsOf: originalURL), originalBytes)
        try assertReaderWidgetPreserved(at: managedURL)

        // Toolbar controls own their clicks even while the direct Comment
        // tool is armed; they cannot create an annotation behind themselves.
        chooseReaderMenuItem("Comment", menu: "PDF Actions", in: pane)
        chooseReaderMenuItem("Zoom In", menu: "PDF Zoom", in: pane)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.pdf.comment"].exists)
        chooseReaderMenuItem("Select", menu: "PDF Actions", in: pane)

        // Repeated toggles exercise collapse, observer teardown and reconnection
        // while preserving the document and already saved annotations.
        for _ in 0..<3 {
            pdfToolbarButton("Hide PDF Reader", in: main).click()
            XCTAssertTrue(
                waitUntil(timeout: 5) {
                    !main.textFields["scholium.pdf.page"].exists
                        && self.pdfToolbarButton("Show PDF Reader", in: main).isHittable
                })
            pdfToolbarButton("Show PDF Reader", in: main).click()
            XCTAssertTrue(main.textFields["scholium.pdf.page"].waitForExistence(timeout: 8))
        }
        pane = main.descendants(matching: .any)["scholium.pdf.pane"]
        let oldWidth = pane.frame.width
        let oldBoundary = pane.frame.minX
        let oldActionsX = pdfToolbarButton("Note Actions", in: main).frame.maxX
        let divider = main.splitGroups["scholium.documentReadingSplit"].splitters.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        divider.click(forDuration: 0.15, thenDragTo: divider.withOffset(CGVector(dx: -70, dy: 0)))
        XCTAssertTrue(waitUntil(timeout: 5) { pane.frame.width > oldWidth + 35 })
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                abs((self.pdfToolbarButton("Note Actions", in: main).frame.maxX - oldActionsX) - (pane.frame.minX - oldBoundary)) <= 5
            }, "Document actions move by the same amount as the native PDF divider.")
        resizeProofWindow(main, toWidth: 900)
        XCTAssertGreaterThanOrEqual(pane.frame.width, 279)
        XCTAssertTrue(main.toolbars.firstMatch.buttons["Search PDF"].isHittable)
        main.buttons["Next PDF Page"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { main.textFields["scholium.pdf.page"].value as? String == "2" })
        chooseReaderMenuItem("Fit PDF", menu: "PDF Zoom", in: pane)
        XCTAssertTrue(waitUntil(timeout: 5) { main.textFields["scholium.pdf.page"].value as? String == "2" })
        let restoredWidth = pane.frame.width
        attachReaderScreenshot("PDF Reader — light, narrow workspace", window: main)

        // Quit through the application command, not terminate(), to prove the
        // save/position/window-session barrier before a stable-session relaunch.
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 20) { self.app.state == .notRunning })
        app = configuredApplication(
            sessionID: sessionID, initialWorkspaceWidth: 900, appearance: .dark, openNote: nil
        )
        app.launch()
        main = app.windows.firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
        pane = main.descendants(matching: .any)["scholium.pdf.pane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 10), "The visible reading pane must restore with its window session.")
        XCTAssertTrue(waitUntil(timeout: 10) { main.textFields["scholium.pdf.page"].value as? String == "2" })
        XCTAssertEqual(pane.frame.width, restoredWidth, accuracy: 30)
        XCTAssertEqual(try source(at: noteURL), boundSource)
        XCTAssertTrue(savedReaderAnnotations(at: managedURL).contains { $0.contents == firstComment })
        XCTAssertTrue(
            savedReaderAnnotations(at: managedURL).contains { $0.value(forAnnotationKey: .subtype) as? String == PDFAnnotationSubtype.highlight.rawValue })
        try assertReaderWidgetPreserved(at: managedURL)
        attachReaderScreenshot("PDF Reader — dark, restored page and pane", window: main)

        chooseReaderMenuItem("Show Annotations", menu: "PDF Actions", in: pane)
        let commentRow = pane.buttons.matching(NSPredicate(format: "label CONTAINS %@", firstComment)).firstMatch
        XCTAssertTrue(commentRow.waitForExistence(timeout: 5))
        commentRow.click()
        let detail = app.descendants(matching: .any)["scholium.pdf.annotation.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let fullComment = detail.staticTexts["scholium.pdf.annotation.contents"]
        XCTAssertTrue(((fullComment.value as? String) ?? fullComment.label).contains(firstComment))
        detail.buttons["scholium.pdf.annotation.edit"].click()
        let revisedComment = "Synthetic lifecycle comment edited after relaunch"
        typeCommittedText(revisedComment, into: readerCommentEditor(), in: app)
        app.buttons["scholium.pdf.comment.save"].click()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                self.savedReaderAnnotations(at: managedURL).contains { $0.contents == revisedComment }
                    && !self.savedReaderAnnotations(at: managedURL).contains { $0.contents == firstComment }
            })
        let revisedRow = pane.buttons.matching(NSPredicate(format: "label CONTAINS %@", revisedComment)).firstMatch
        XCTAssertTrue(revisedRow.waitForExistence(timeout: 5))
        revisedRow.click()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        detail.buttons["scholium.pdf.annotation.edit"].click()
        app.buttons["Delete Annotation"].click()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                let annotations = self.savedReaderAnnotations(at: managedURL)
                return !annotations.contains { $0.value(forAnnotationKey: .subtype) as? String == PDFAnnotationSubtype.text.rawValue }
                    && annotations.contains { $0.value(forAnnotationKey: .subtype) as? String == PDFAnnotationSubtype.highlight.rawValue }
            })

        let missingURL = testDirectory.appendingPathComponent("Temporarily Missing Reader.pdf")
        try FileManager.default.moveItem(at: managedURL, to: missingURL)
        defer {
            if FileManager.default.fileExists(atPath: missingURL.path),
                !FileManager.default.fileExists(atPath: managedURL.path)
            {
                try? FileManager.default.moveItem(at: missingURL, to: managedURL)
            }
        }
        chooseReaderMenuItem("Reload PDF", menu: "PDF Actions", in: pane)
        let missingError = pane.descendants(matching: .any)["scholium.pdf.error"]
        XCTAssertTrue(missingError.waitForExistence(timeout: 10))
        XCTAssertFalse(main.textFields["scholium.pdf.page"].exists)
        chooseReaderMenuItem("Attach or Replace PDF…", menu: "PDF Actions", in: pane)
        XCTAssertTrue(app.buttons["scholium.pdf.chooseFile"].waitForExistence(timeout: 5))
        app.sheets.firstMatch.buttons["Cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !self.app.buttons["scholium.pdf.chooseFile"].exists })
        XCTAssertEqual(try source(at: noteURL), boundSource)
        try FileManager.default.moveItem(at: missingURL, to: managedURL)
        pane.buttons["Retry PDF"].click()
        XCTAssertTrue(main.textFields["scholium.pdf.page"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 5) { !missingError.exists })
        XCTAssertEqual(try Data(contentsOf: originalURL), originalBytes)
        XCTAssertEqual(
            savedReaderAnnotations(at: originalURL).map { $0.value(forAnnotationKey: .subtype) as? String },
            [PDFAnnotationSubtype.widget.rawValue])
        XCTAssertTrue(
            savedReaderAnnotations(at: managedURL).contains { $0.value(forAnnotationKey: .subtype) as? String == PDFAnnotationSubtype.highlight.rawValue })
        try assertReaderWidgetPreserved(at: managedURL)

        let summaryEvidence = XCTAttachment(
            string:
                "Native PDF reader: attachment and picker cancellation; exact note bytes outside pdf binding; "
                + "highlight and comment save/edit/delete; three hide/show cycles; divider resize; page 2 and pane "
                + "restoration after Cmd-Q; missing-copy reload and recovery; original widget flags/value preserved. Original PDF SHA256: "
                + SHA256.hash(data: originalBytes).map { String(format: "%02x", $0) }.joined())
        summaryEvidence.name = "PDF lifecycle and original preservation"
        summaryEvidence.lifetime = .keepAlways
        add(summaryEvidence)
    }

    @MainActor
    private func pdfToolbarButton(_ label: String, in window: XCUIElement) -> XCUIElement {
        window.toolbars.firstMatch.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func verifyReaderPaneVisibilityMatrix(in window: XCUIElement) {
        var closedActionsX: CGFloat?
        for (pdfVisible, inspectorVisible, name) in [
            (false, false, "editor only"), (true, false, "PDF only"),
            (false, true, "Inspector replaces PDF"), (false, false, "Inspector closes"),
            (false, true, "Inspector only"), (true, false, "PDF replaces Inspector"),
        ] {
            if pdfVisible {
                pdfToolbarButton("Show PDF Reader", in: window).click()
            } else if inspectorVisible {
                pdfToolbarButton("Show Research Inspector", in: window).click()
            } else {
                let hidePDF = pdfToolbarButton("Hide PDF Reader", in: window)
                let hideInspector = pdfToolbarButton("Hide Research Inspector", in: window)
                if hidePDF.exists { hidePDF.click() } else if hideInspector.exists { hideInspector.click() }
            }
            let pdf = window.descendants(matching: .any)["scholium.pdf.pane"]
            let inspector = window.descendants(matching: .any)["scholium.researchInspector"]
            XCTAssertTrue(waitUntil(timeout: 8) { pdf.exists == pdfVisible && inspector.exists == inspectorVisible })
            let noteActions = pdfToolbarButton("Note Actions", in: window)
            if pdfVisible || inspectorVisible {
                let sidePane = pdfVisible ? pdf : inspector
                XCTAssertTrue(
                    waitUntil(timeout: 5) { abs(noteActions.frame.maxX - sidePane.frame.minX) <= 10 }, "Document actions track the visible side-pane boundary.")
            } else if let closedActionsX {
                XCTAssertTrue(
                    waitUntil(timeout: 5) { abs(noteActions.frame.maxX - closedActionsX) <= 5 },
                    "Closing either side pane restores the same document toolbar layout.")
            } else {
                closedActionsX = noteActions.frame.maxX
            }
            for (visible, show, hide) in [
                (pdfVisible, "Show PDF Reader", "Hide PDF Reader"),
                (inspectorVisible, "Show Research Inspector", "Hide Research Inspector"),
            ] {
                let result = pdfToolbarButton(visible ? hide : show, in: window)
                XCTAssertTrue(waitUntil(timeout: 5) { result.isHittable })
                XCTAssertEqual((result.value as? NSNumber)?.intValue, visible ? 1 : 0)
            }
            attachReaderScreenshot("PDF Reader — exclusive pane transitions, \(name)", window: window)
        }
    }

    @MainActor
    private func openReaderMenu(_ menu: String) {
        let identifiers = ["PDF Actions": "scholium.pdf.actions", "PDF Zoom": "scholium.pdf.zoom"]
        let toolbar = app.windows.firstMatch.toolbars.firstMatch
        let control =
            menu == "PDF Actions"
            ? pdfToolbarButton("PDF Actions", in: app.windows.firstMatch)
            : app.windows.firstMatch.descendants(matching: .any)[identifiers[menu]!]
        if menu == "PDF Zoom" {
            let pane = app.windows.firstMatch.descendants(matching: .any)["scholium.pdf.pane"]
            pane.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.25)).hover()
            XCTAssertTrue(control.waitForExistence(timeout: 5) && control.isEnabled)
            control.click()
            return
        }
        if control.exists && control.isHittable {
            control.click()
        } else {
            let compact = toolbar.menuButtons["PDF Reader"]
            XCTAssertTrue(compact.waitForExistence(timeout: 5))
            compact.click()
            let submenu = app.menuItems[identifiers[menu]! + ".group"]
            XCTAssertTrue(submenu.waitForExistence(timeout: 3))
            submenu.hover()
        }
    }

    @MainActor
    private func chooseReaderMenuItem(_ title: String, menu: String, in pane: XCUIElement) {
        if menu == "PDF Actions", let tool = ["Select": "select", "Highlight": "highlight", "Comment": "comment"][title] {
            pane.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.25)).hover()
            let button = pane.descendants(matching: .any)["scholium.pdf.tool." + tool]
            XCTAssertTrue(button.waitForExistence(timeout: 5) && button.isEnabled)
            button.click()
            XCTAssertEqual((button.value as? NSNumber)?.intValue, 1)
            return
        }
        let identifiers = ["PDF Actions": "scholium.pdf.actions", "PDF Zoom": "scholium.pdf.zoom"]
        openReaderMenu(menu)
        let commands = [
            "Attach or Replace PDF…": "attach", "Detach PDF": "detach", "Export PDF…": "export", "Reload PDF": "reload",
            "Zoom In": "zoomIn", "Zoom Out": "zoomOut", "Fit PDF": "fit",
            "Select": "selectTool", "Highlight": "highlightTool", "Comment": "commentTool",
            "Highlight Selection": "highlight", "Add PDF Comment…": "comment", "Show Annotations": "showAnnotations",
        ]
        let item = app.menuItems["\(identifiers[menu]!).\(commands[title]!)"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        XCTAssertTrue(item.isEnabled, "\(title) must remain an available native command.")
        item.click()
    }

    @MainActor
    private func readerCommentEditor() -> XCUIElement {
        let editor = app.descendants(matching: .any)["scholium.pdf.comment"]
        _ = editor.waitForExistence(timeout: 5)
        let textView = editor.textViews.firstMatch
        return textView.exists ? textView : editor
    }

    @MainActor
    private func exerciseBoundedReaderHighlightDrag(in pane: XCUIElement, managedURL: URL) {
        let nativePDF = pane.scrollViews.firstMatch
        let visibleLine = nativePDF.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Pointer Highlight Marker", "Pointer Highlight Marker")
        ).allElementsBoundByIndex.first {
            $0.isHittable && $0.frame.width > 40 && $0.frame.height >= 8
                && $0.frame.height <= 48 && nativePDF.frame.contains($0.frame)
        }
        guard let visibleLine else {
            let evidence = XCTAttachment(
                string:
                    "The native PDF accessibility tree did not expose a bounded single-line text frame. "
                    + "The pointer highlighter drag was not attempted; search selection and Highlight Selection remain the verified route.")
            evidence.name = "Pointer highlighter geometry requires native inspection"
            evidence.lifetime = .keepAlways
            add(evidence)
            return
        }
        chooseReaderMenuItem("Highlight", menu: "PDF Actions", in: pane)
        let countBefore = savedReaderAnnotations(at: managedURL).filter {
            $0.value(forAnnotationKey: .subtype) as? String == PDFAnnotationSubtype.highlight.rawValue
        }.count
        visibleLine.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).click(
            forDuration: 0.15,
            thenDragTo: visibleLine.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5))
        )
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                self.savedReaderAnnotations(at: managedURL).filter {
                    $0.value(forAnnotationKey: .subtype) as? String == PDFAnnotationSubtype.highlight.rawValue
                }.count > countBefore
            }, "Dragging the native Highlight tool over a bounded line must persist a highlight.")
        chooseReaderMenuItem("Select", menu: "PDF Actions", in: pane)
    }

    @MainActor
    private func chooseReaderPDFInNativePanel(_ url: URL) {
        let panel = app.descendants(matching: .any)["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields["PathTextField"].firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        typeCommittedText(url.path, into: path, in: app)
        // Native completion changes this sheet's button collection while the
        // path resolves. Return addresses the focused native field directly.
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 10) { !path.exists || !path.isHittable })
        if panel.exists {
            let open = panel.buttons["OKButton"]
            XCTAssertTrue(open.waitForExistence(timeout: 5))
            XCTAssertTrue(waitUntil(timeout: 10) { open.isEnabled && open.isHittable })
            open.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
        XCTAssertTrue(waitUntil(timeout: 5) { !panel.exists })
    }

    @MainActor
    private func chooseReaderExportDestination(_ url: URL) {
        let panel = app.descendants(matching: .any)["save-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields["PathTextField"].firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        typeCommittedText(url.deletingLastPathComponent().path, into: path, in: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 10) { !path.exists || !path.isHittable })
        let name = panel.textFields.firstMatch
        XCTAssertTrue(name.exists)
        typeCommittedText(url.lastPathComponent, into: name, in: app)
        let save = panel.buttons["OKButton"]
        XCTAssertTrue(save.exists && save.isEnabled)
        save.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !panel.exists })
    }

    private func readerPDFBinding(in source: String) throws -> String {
        let expression = try NSRegularExpression(pattern: "(?m)^pdf: ([^\\r\\n]+)(?:\\r?\\n|$)")
        let match = try XCTUnwrap(expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        let valueRange = try XCTUnwrap(Range(match.range(at: 1), in: source))
        let value = String(source[valueRange])
        return value.hasPrefix("\"") ? try JSONDecoder().decode(String.self, from: Data(value.utf8)) : value
    }

    private func sourceWithoutPDFBinding(_ source: String) throws -> String {
        let expression = try NSRegularExpression(pattern: "(?m)^pdf: [^\\r\\n]+(?:\\r?\\n|$)")
        let match = try XCTUnwrap(expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        let range = try XCTUnwrap(Range(match.range, in: source))
        return source.replacingCharacters(in: range, with: "")
    }

    private func savedReaderAnnotations(at url: URL) -> [PDFAnnotation] {
        guard let document = PDFDocument(url: url) else { return [] }
        return (0..<document.pageCount).flatMap { document.page(at: $0)?.annotations ?? [] }
    }

    private func assertReaderWidgetPreserved(at url: URL) throws {
        let widget = try XCTUnwrap(savedReaderAnnotations(at: url).first { $0.fieldName == "SyntheticWidget" })
        XCTAssertEqual(widget.widgetStringValue, "Synthetic widget value")
        XCTAssertFalse(widget.isReadOnly)
        XCTAssertEqual((widget.annotationKeyValues[PDFAnnotationKey.widgetFieldFlags.rawValue] as? NSNumber)?.intValue, 0)
    }

    @MainActor
    private func attachReaderScreenshot(_ title: String, window: XCUIElement) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeSearchableReaderPDF(at url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for text in ["Scholium PDF Lifecycle Quartz", "Scholium PDF Lifecycle Second Page"] {
            context.beginPDFPage(nil)
            let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
            let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes) as CFAttributedString)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: 72, y: 640)
            CTLineDraw(line, context)
            let pointerLine = CTLineCreateWithAttributedString(
                NSAttributedString(string: "Pointer Highlight Marker", attributes: attributes) as CFAttributedString
            )
            context.textPosition = CGPoint(x: 72, y: 590)
            CTLineDraw(pointerLine, context)
            context.endPDFPage()
        }
        context.closePDF()
        let document = try XCTUnwrap(PDFDocument(url: url))
        let widget = PDFAnnotation(bounds: CGRect(x: 72, y: 530, width: 250, height: 30), forType: .widget, withProperties: nil)
        widget.widgetFieldType = .text
        widget.fieldName = "SyntheticWidget"
        widget.widgetStringValue = "Synthetic widget value"
        widget.setValue(NSNumber(value: 0), forAnnotationKey: .widgetFieldFlags)
        try XCTUnwrap(document.page(at: 0)).addAnnotation(widget)
        XCTAssertTrue(document.write(to: url))
    }
}
