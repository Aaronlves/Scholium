import AppKit
import CoreGraphics
import CoreText
import CryptoKit
import PDFKit
@preconcurrency import XCTest

extension ScholiumUITests {
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
        pane.buttons["scholium.pdf.attach"].click()
        let chooseFile = app.buttons["scholium.pdf.chooseFile"]
        XCTAssertTrue(chooseFile.waitForExistence(timeout: 5))
        chooseFile.click()
        chooseReaderPDFInNativePanel(originalURL)
        let page = main.textFields["scholium.pdf.page"]
        XCTAssertTrue(page.waitForExistence(timeout: 15))
        resizeProofWindow(main, toWidth: 900)
        let divider = main.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: pane.frame.minX - main.frame.minX - 1, dy: pane.frame.midY - main.frame.minY))
        divider.click(forDuration: 0.15, thenDragTo: divider.withOffset(CGVector(dx: pane.frame.width - 280, dy: 0)))
        XCTAssertTrue(waitUntil(timeout: 5) { pane.frame.width >= 279 && pane.frame.width <= 300 })
        XCTAssertEqual(page.label, "PDF Page")
        let compact = main.toolbars.firstMatch.descendants(matching: .any)["scholium.pdf.compactControls"]
        XCTAssertTrue(waitUntil(timeout: 5) { compact.isHittable })
        XCTAssertEqual(compact.label, "PDF Reader")
        XCTAssertGreaterThanOrEqual(page.frame.minX, pane.frame.minX - 2)
        XCTAssertGreaterThanOrEqual(compact.frame.minX, pane.frame.minX - 2)
        let more = pdfToolbarButton("Note Actions", in: main)
        XCTAssertLessThanOrEqual(more.frame.maxX, pane.frame.minX + 2)
        typeCommittedText("2", into: page, in: app)
        page.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "2" })
        // Actual Tab/Space reaches the compact native menu. Every full-size
        // command remains available, including page navigation and Search.
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(app.menuItems["Search PDF"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Previous PDF Page"].firstMatch.isEnabled)
        XCTAssertFalse(app.menuItems["Next PDF Page"].firstMatch.isEnabled)
        for label in ["PDF Zoom", "PDF Annotations", "PDF Actions"] {
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
        typeCommittedText("NoSuchPDFPassage synthetic __", into: search, in: app)
        search.typeKey(.return, modifierFlags: [])
        let noMatch = app.staticTexts["No matches in this PDF."]
        XCTAssertTrue(noMatch.waitForExistence(timeout: 3), "Return submits the PDF search.")
        typeCommittedText("Lifecycle Quartz", into: search, in: app)
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
        let widerDivider = main.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: pane.frame.minX - main.frame.minX - 1, dy: pane.frame.midY - main.frame.minY))
        widerDivider.click(forDuration: 0.15, thenDragTo: widerDivider.withOffset(CGVector(dx: -300, dy: 0)))
        let fullSearch = main.toolbars.firstMatch.buttons["scholium.pdf.search.toggle"]
        XCTAssertTrue(waitUntil(timeout: 5) { fullSearch.isHittable && !compact.isHittable })
        XCTAssertGreaterThanOrEqual(page.frame.minX, pane.frame.minX - 2)
        XCTAssertLessThanOrEqual(more.frame.maxX, pane.frame.minX + 2)
        attachReaderScreenshot("PDF Reader — wide native controls restored within reader region", window: main)
        typeCommittedText("2", into: page, in: app)
        page.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { page.value as? String == "2" })
        app.typeKey("p", modifierFlags: [.control, .command])
        XCTAssertTrue(waitUntil(timeout: 5) { !page.exists })
        app.typeKey("p", modifierFlags: [.control, .command])
        XCTAssertTrue(page.waitForExistence(timeout: 5))
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
        XCTAssertLessThan(nativePDF.frame.minY - pane.frame.minY, 55, "PDF paper starts at the native toolbar edge, without a stacked reader header.")
        XCTAssertEqual(nativePDF.frame.maxY, pane.frame.maxY, accuracy: 5, "Toolbar controls do not shorten the PDF scrolling surface.")
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

        main.toolbars.firstMatch.buttons["scholium.pdf.search.toggle"].click()
        let search = app.textFields["scholium.pdf.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        typeCommittedText("Lifecycle Quartz", into: search, in: app)
        search.typeKey(.return, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })
        chooseReaderMenuItem("Highlight Selection", menu: "PDF Annotations", in: pane)
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                self.savedReaderAnnotations(at: managedURL).contains {
                    $0.value(forAnnotationKey: .subtype) as? String == PDFAnnotationSubtype.highlight.rawValue
                }
            }, "The native selection highlight must be saved in the managed copy.")
        exerciseBoundedReaderHighlightDrag(in: pane, managedURL: managedURL)

        let firstComment = "Synthetic lifecycle comment"
        chooseReaderMenuItem("Add PDF Comment…", menu: "PDF Annotations", in: pane)
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
        chooseReaderMenuItem("Comment", menu: "PDF Annotations", in: pane)
        chooseReaderMenuItem("Zoom In", menu: "PDF Zoom", in: pane)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.pdf.comment"].exists)
        chooseReaderMenuItem("Select", menu: "PDF Annotations", in: pane)

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
        let divider = main.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: pane.frame.minX - main.frame.minX - 1, dy: pane.frame.midY - main.frame.minY)
        )
        divider.click(forDuration: 0.15, thenDragTo: divider.withOffset(CGVector(dx: -70, dy: 0)))
        XCTAssertTrue(waitUntil(timeout: 5) { pane.frame.width > oldWidth + 35 })
        resizeProofWindow(main, toWidth: 900)
        XCTAssertGreaterThanOrEqual(pane.frame.width, 279)
        XCTAssertTrue(main.toolbars.firstMatch.buttons["scholium.pdf.search.toggle"].isHittable)
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

        chooseReaderMenuItem("Show Annotations", menu: "PDF Annotations", in: pane)
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
        let identifiers = ["PDF Actions": "scholium.pdf.actions", "PDF Zoom": "scholium.pdf.zoom", "PDF Annotations": "scholium.pdf.annotations"]
        let toolbar = app.windows.firstMatch.toolbars.firstMatch
        let control = toolbar.descendants(matching: .any)[identifiers[menu]!]
        if control.exists && control.isHittable {
            control.click()
        } else {
            let compact = toolbar.descendants(matching: .any)["scholium.pdf.compactControls"]
            XCTAssertTrue(compact.waitForExistence(timeout: 5))
            compact.click()
            let submenu = app.menuItems[identifiers[menu]! + ".group"]
            XCTAssertTrue(submenu.waitForExistence(timeout: 3))
            submenu.hover()
        }
    }

    @MainActor
    private func chooseReaderMenuItem(_ title: String, menu: String, in pane: XCUIElement) {
        let identifiers = ["PDF Actions": "scholium.pdf.actions", "PDF Zoom": "scholium.pdf.zoom", "PDF Annotations": "scholium.pdf.annotations"]
        openReaderMenu(menu)
        let commands = [
            "Attach or Replace PDF…": "attach", "Reload PDF": "reload",
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
        chooseReaderMenuItem("Highlight", menu: "PDF Annotations", in: pane)
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
        chooseReaderMenuItem("Select", menu: "PDF Annotations", in: pane)
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
        XCTAssertTrue(waitUntil(timeout: 5) { !path.exists })
        if panel.exists {
            let open = panel.buttons["OKButton"]
            XCTAssertTrue(open.waitForExistence(timeout: 5))
            open.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
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
