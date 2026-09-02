@preconcurrency import XCTest
import AppKit
import CryptoKit
import notify

extension ScholiumUITests {
    @MainActor
    func testInspectorDividerResizesWithoutInteractiveCollapse() throws {
        let inspector = app.scrollViews["scholium.researchInspector"].firstMatch
        if !inspector.exists {
            app.typeKey("b", modifierFlags: [.command, .option])
        }
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        let initialFrame = inspector.frame
        XCTAssertGreaterThan(initialFrame.width, 0)

        func dragDivider(by horizontalDelta: CGFloat) throws {
            let inspectorFrame = inspector.frame
            let divider = try XCTUnwrap(
                app.descendants(matching: .splitter)
                    .allElementsBoundByIndex
                    .first { candidate in
                        let frame = candidate.frame
                        return frame.width <= 2
                            && frame.height >= inspectorFrame.height
                            && abs(frame.midX - inspectorFrame.minX) <= 2
                    }
            )
            let start = divider.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            )
            start.click(
                forDuration: 0.35,
                thenDragTo: start.withOffset(CGVector(dx: horizontalDelta, dy: 0)),
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
        }

        try dragDivider(by: -100)
        XCTAssertTrue(waitUntil(timeout: 5) {
            inspector.frame.width >= initialFrame.width + 70
                && abs(inspector.frame.maxX - initialFrame.maxX) <= 2
        })

        let expandedFrame = inspector.frame
        try dragDivider(by: 500)
        XCTAssertTrue(waitUntil(timeout: 5) {
            inspector.exists
                && inspector.frame.width < expandedFrame.width - 70
                && inspector.frame.width >= 250
                && abs(inspector.frame.maxX - initialFrame.maxX) <= 2
        })

        let minimumFrame = inspector.frame
        try dragDivider(by: -80)
        XCTAssertTrue(waitUntil(timeout: 5) {
            inspector.frame.width >= minimumFrame.width + 50
                && abs(inspector.frame.maxX - initialFrame.maxX) <= 2
        })

        let stableInspectorFrame = inspector.frame
        let toolbar = app.toolbars.firstMatch
        let library = app.descendants(matching: .any)["scholium.librarySurface"]
        XCTAssertTrue(toolbar.waitForExistence(timeout: 5))
        XCTAssertTrue(library.waitForExistence(timeout: 5))

        let hideSidebar = toolbar.buttons["Hide Sidebar"].firstMatch
        XCTAssertTrue(hideSidebar.waitForExistence(timeout: 5))
        hideSidebar.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(waitUntil(timeout: 5) {
            !library.exists
                && abs(inspector.frame.width - stableInspectorFrame.width) <= 2
                && abs(inspector.frame.maxX - stableInspectorFrame.maxX) <= 2
        })

        let showSidebar = toolbar.buttons["Show Sidebar"].firstMatch
        XCTAssertTrue(showSidebar.waitForExistence(timeout: 5))
        showSidebar.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(waitUntil(timeout: 5) {
            library.exists
                && abs(inspector.frame.width - stableInspectorFrame.width) <= 2
                && abs(inspector.frame.maxX - stableInspectorFrame.maxX) <= 2
        })
    }

    /// A completed primary click on the Folder row—not only its disclosure
    /// triangle—must use the native outline action and toggle every time.
    @MainActor
    func testNativeFolderRowClickTogglesDisclosure() throws {
        let folder = app.descendants(matching: .any)[
            "scholium.folderRow.Cluster-01"
        ].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        XCTAssertEqual(folder.value as? String, "Collapsed")

        folder.click()
        XCTAssertTrue(waitUntil(timeout: 5) {
            (folder.value as? String) == "Expanded"
        })
        let child = app.descendants(matching: .any)[
            "scholium.noteRow.Cluster-01/analysis-007.md"
        ].firstMatch
        XCTAssertTrue(child.waitForExistence(timeout: 5))

        folder.click()
        XCTAssertTrue(waitUntil(timeout: 5) {
            (folder.value as? String) == "Collapsed"
                && !child.exists
        })
    }

    /// NSOutlineView owns the populated hierarchy's process-private drag
    /// source, destination validation, auto-scroll, native drop state, and row
    /// reuse. The committed source-ahead move must replace the source row before
    /// the complete Workspace refresh finishes.
    @MainActor
    func testNativeSidebarDropPublishesMovedNoteImmediately() throws {
        let noteList = app.descendants(matching: .any)[
            "scholium.noteList"
        ].firstMatch
        let source = app.descendants(matching: .any)[
            "scholium.noteRow.QA Autosave B.md"
        ].firstMatch
        let target = app.descendants(matching: .any)[
            "scholium.folderRow.Fixture Assets"
        ].firstMatch
        XCTAssertTrue(noteList.waitForExistence(timeout: 10))
        scrollUntilHittable(source, in: noteList)
        scrollUntilHittable(target, in: noteList)
        XCTAssertTrue(source.isHittable)
        XCTAssertTrue(target.isHittable)
        let sourceURL = triptychDirectory.appendingPathComponent(
            "01-analyses/QA Autosave B.md"
        )
        let destinationURL = triptychDirectory.appendingPathComponent(
            "01-analyses/Fixture Assets/QA Autosave B.md"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))

        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(
                forDuration: 0.35,
                thenDragTo: target.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                ),
                withVelocity: .slow,
                thenHoldForDuration: 0.35
            )

        XCTAssertTrue(waitUntil(timeout: 10) {
            FileManager.default.fileExists(atPath: destinationURL.path)
                && !FileManager.default.fileExists(atPath: sourceURL.path)
        })
        let destination = app.descendants(matching: .any)[
            "scholium.noteRow.Fixture Assets/QA Autosave B.md"
        ].firstMatch
        scrollUntilHittable(destination, in: noteList)
        XCTAssertTrue(
            destination.waitForExistence(timeout: 5),
            "The committed move did not publish its destination row immediately."
        )
        XCTAssertFalse(source.exists)
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", timeout: 5))
    }

    /// The fixed LibraryHeader—not unoccupied outline space or a root Note
    /// row—is the native pointer target for moving an item back to the vault
    /// root. The source-ahead projection must publish that root row at commit.
    @MainActor
    func testNativeLibraryHeaderDropMovesNoteToVaultRoot() throws {
        let noteList = app.descendants(matching: .any)[
            "scholium.noteList"
        ].firstMatch
        let folder = app.descendants(matching: .any)[
            "scholium.folderRow.Cluster-01"
        ].firstMatch
        let libraryHeader = app.descendants(matching: .any)[
            "scholium.libraryHeader"
        ].firstMatch
        XCTAssertTrue(noteList.waitForExistence(timeout: 10))
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        XCTAssertTrue(libraryHeader.waitForExistence(timeout: 5))

        if (folder.value as? String) != "Expanded" {
            folder.click()
            XCTAssertTrue(waitUntil(timeout: 5) {
                (folder.value as? String) == "Expanded"
            })
        }

        let source = app.descendants(matching: .any)[
            "scholium.noteRow.Cluster-01/analysis-007.md"
        ].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        scrollUntilHittable(source, in: noteList)
        XCTAssertTrue(source.isHittable)
        XCTAssertTrue(libraryHeader.isHittable)

        let sourceURL = triptychDirectory.appendingPathComponent(
            "01-analyses/Cluster-01/analysis-007.md"
        )
        let destinationURL = triptychDirectory.appendingPathComponent(
            "01-analyses/analysis-007.md"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))

        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(
                forDuration: 0.35,
                thenDragTo: libraryHeader.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                ),
                withVelocity: .slow,
                thenHoldForDuration: 0.35
            )

        let destination = app.descendants(matching: .any)[
            "scholium.noteRow.analysis-007.md"
        ].firstMatch
        XCTAssertTrue(
            destination.waitForExistence(timeout: 5),
            "The LibraryHeader drop did not publish the root Note row."
        )
        XCTAssertFalse(source.exists)
        XCTAssertTrue(waitUntil(timeout: 5) {
            FileManager.default.fileExists(atPath: destinationURL.path)
                && !FileManager.default.fileExists(atPath: sourceURL.path)
        })
    }

    /// A durable Folder move must update the exact window's native outline
    /// before the complete graph, Search, and research projections refresh.
    @MainActor
    func testNativeFolderDropPublishesMovedFolderImmediately() throws {
        let noteList = app.descendants(matching: .any)[
            "scholium.noteList"
        ].firstMatch
        let source = app.descendants(matching: .any)[
            "scholium.folderRow.Cluster-01"
        ].firstMatch
        let target = app.descendants(matching: .any)[
            "scholium.folderRow.Cluster-02"
        ].firstMatch
        XCTAssertTrue(noteList.waitForExistence(timeout: 10))
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(target.waitForExistence(timeout: 5))

        if (target.value as? String) != "Expanded" {
            target.click()
            XCTAssertTrue(waitUntil(timeout: 5) {
                (target.value as? String) == "Expanded"
            })
        }
        scrollUntilHittable(source, in: noteList)
        scrollUntilHittable(target, in: noteList)

        let sourceURL = triptychDirectory.appendingPathComponent(
            "01-analyses/Cluster-01"
        )
        let destinationURL = triptychDirectory.appendingPathComponent(
            "01-analyses/Cluster-02/Cluster-01"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))

        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(
                forDuration: 0.35,
                thenDragTo: target.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                ),
                withVelocity: .slow,
                thenHoldForDuration: 0.35
            )

        let destination = app.descendants(matching: .any)[
            "scholium.folderRow.Cluster-02/Cluster-01"
        ].firstMatch
        XCTAssertTrue(
            destination.waitForExistence(timeout: 5),
            "The committed Folder move waited for disposable Workspace projections."
        )
        XCTAssertFalse(source.exists)
        XCTAssertTrue(waitUntil(timeout: 5) {
            FileManager.default.fileExists(atPath: destinationURL.path)
                && !FileManager.default.fileExists(atPath: sourceURL.path)
        })
    }

    /// The default final QA route. It keeps one isolated application process
    /// alive for the complete journey so the researcher does not see a new QA
    /// app open for every assertion group.
    @MainActor
    func testStorageUnavailableRetriesWithoutConstructingWorkspace() throws {
        let unavailable = app.descendants(matching: .any)[
            "scholium.storageUnavailable"
        ]
        let retry = app.buttons["Retry"]
        let details = app.buttons["Details"].firstMatch
        let detailsContent = app.descendants(matching: .any)[
            "scholium.storageUnavailable.details"
        ]
        let renderedDocument = app.descendants(matching: .any)["Rendered Markdown"]
        let window = app.windows.firstMatch

        XCTAssertTrue(unavailable.exists)
        XCTAssertTrue(app.staticTexts["Storage Unavailable"].exists)
        XCTAssertTrue(retry.exists)
        XCTAssertTrue(retry.isEnabled)
        XCTAssertTrue(app.buttons["Quit"].exists)
        XCTAssertFalse(renderedDocument.exists)
        XCTAssertFalse(detailsContent.exists)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                window.frame.width >= 480
                    && window.frame.width <= 560
                    && window.frame.height >= 190
                    && window.frame.height <= 320
            },
            "The collapsed storage-recovery window must fit its compact content."
        )
        let collapsedFrame = window.frame

        XCTAssertTrue(details.exists)
        XCTAssertEqual(details.value as? String, "Collapsed")
        details.click()
        XCTAssertEqual(details.value as? String, "Expanded")
        XCTAssertTrue(detailsContent.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                window.frame.width >= 480
                    && window.frame.width <= 560
                    && window.frame.height > collapsedFrame.height
                    && window.frame.height <= 380
            },
            "Expanding storage details must grow only the compact recovery window."
        )

        app.menuBars.menuBarItems["File"].click()
        let newNote = app.menuItems["New Note"].firstMatch
        if newNote.exists {
            XCTAssertFalse(newNote.isEnabled)
        }
        app.typeKey(.escape, modifierFlags: [])

        app.staticTexts["Storage Unavailable"].click()
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 15) {
                unavailable.exists
                    && retry.isEnabled
                    && !detailsContent.exists
                    && window.frame.width >= 480
                    && window.frame.width <= 560
                    && window.frame.height >= 190
                    && window.frame.height <= 320
            },
            "A failed Retry must remount the same compact recovery state."
        )

        let blocker = homeDirectory.appendingPathComponent("ApplicationSupport")
        try FileManager.default.removeItem(at: blocker)
        app.staticTexts["Storage Unavailable"].click()
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            waitUntil(timeout: 90) { self.documentSurfaceIsUsable() },
            "The default Retry action did not enter the Workspace after storage was repaired."
        )
        XCTAssertFalse(unavailable.exists)
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                window.frame.width >= 1_200
                    && window.frame.height >= 650
            },
            "Successful Retry must restore the workspace frame after compact recovery."
        )
    }

    @MainActor
    func testSharedSearchMatchesAnAliasAcrossTheTriptych() throws {
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))

        app.typeKey("f", modifierFlags: [.command, .shift])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))

        let field = app.descendants(matching: .any)["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let triptych = app.buttons["scholium.searchScope.triptych"]
        XCTAssertTrue(triptych.waitForExistence(timeout: 5))
        triptych.click()
        typeCommittedText("Normative QA Nexus", into: field, in: app)

        let result = searchResult(named: "QA Topic")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.click()

        XCTAssertTrue(waitUntil(timeout: 8) {
            self.documentTitle() == "QA Topic"
        })
        XCTAssertTrue(app.buttons["scholium.vault.topic_knowledge"].exists)
        XCTAssertFalse(search.exists)
    }

    @MainActor
    func testManagedNewNoteKeepsFixedYAMLAfterAddingCustomMetadataField() throws {
        let libraryFilters = app.descendants(matching: .any)[
            "scholium.libraryFilters"
        ]
        XCTAssertTrue(libraryFilters.waitForExistence(timeout: 10))
        libraryFilters.click()
        let attentionFilter = app.menuItems["Needs Attention"].firstMatch
        XCTAssertTrue(attentionFilter.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { attentionFilter.isEnabled })
        attentionFilter.click()
        let filterStatus = app.descendants(matching: .any)[
            "scholium.libraryFilterStatus"
        ]
        XCTAssertTrue(filterStatus.waitForExistence(timeout: 5))

        let keyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
        func createAndType(
            path: String,
            initialSource: String,
            marker: String
        ) throws {
            let libraryCreate = app.descendants(matching: .any)[
                "scholium.libraryCreate"
            ]
            XCTAssertTrue(libraryCreate.waitForExistence(timeout: 10))
            libraryCreate.click()
            let newNote = app.descendants(matching: .any)["scholium.newNote"]
            XCTAssertTrue(newNote.waitForExistence(timeout: 3))
            XCTAssertTrue(app.descendants(matching: .any)["scholium.newFolder"].exists)

            newNote.click()
            XCTAssertFalse(
                app.buttons["Create"].firstMatch.waitForExistence(timeout: 1),
                "Direct note creation must not present a naming or Metadata sheet."
            )
            let createdURL = triptychDirectory.appendingPathComponent(
                "01-analyses/\(path)"
            )
            XCTAssertTrue(waitUntil(timeout: 10) {
                (try? self.source(at: createdURL)) == initialSource
            })

            let editor = app.descendants(matching: .any)[
                "Markdown editor, Edit mode"
            ].firstMatch
            XCTAssertTrue(
                editor.waitForExistence(timeout: 20),
                "Managed New Note must present Edit as its creation destination."
            )
            XCTAssertTrue(
                waitUntil(timeout: 5) { keyboardFocus.evaluate(with: editor) },
                "Managed New Note must focus its exact body insertion point."
            )
            editor.typeText(marker)
            XCTAssertTrue(
                waitUntil(timeout: 5) {
                    (editor.value as? String)?.contains(marker) == true
                },
                "The first keystroke must be accepted by the focused editor."
            )
            XCTAssertTrue(waitUntil(timeout: 12) {
                (try? self.source(at: createdURL)) == initialSource + marker
            })
        }

        let firstMarker = "cold-no-seed-first-keystroke\n"
        let fixedYAML = "---\nsummary: null\nkeywords: []\n---\n"
        try createAndType(
            path: "Untitled.md",
            initialSource: fixedYAML,
            marker: firstMarker
        )

        XCTAssertTrue(waitUntil(timeout: 10) {
            !filterStatus.exists
                && (libraryFilters.value as? String) == "No filters active"
        })
        let createdRow = app.descendants(matching: .any)[
            "scholium.noteRow.Untitled.md"
        ]
        XCTAssertTrue(createdRow.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 5) { createdRow.isSelected })
        XCTAssertTrue(waitForDocumentTitle("Untitled", timeout: 20))

        let appMenu = app.menuBars.menuBarItems["Scholium QA"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()
        let settingsWindow = app.windows.matching(
            identifier: "com_apple_SwiftUI_Settings_window"
        ).firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 8))
        let metadataPane = settingsWindow.descendants(matching: .any)[
            "Metadata"
        ].firstMatch
        XCTAssertTrue(metadataPane.waitForExistence(timeout: 8))
        metadataPane.click()
        let retryMetadata = settingsWindow.buttons["Retry Metadata Settings"]
        if retryMetadata.waitForExistence(timeout: 2) {
            retryMetadata.click()
        }
        let addField = settingsWindow.descendants(matching: .any)[
            "scholium.metadataSettings.addField"
        ].firstMatch
        XCTAssertTrue(addField.waitForExistence(timeout: 10))
        addField.click()
        let fieldKey = settingsWindow.descendants(matching: .any)[
            "scholium.metadataSettings.fieldKey"
        ].firstMatch
        XCTAssertTrue(fieldKey.waitForExistence(timeout: 5))
        fieldKey.click()
        fieldKey.typeText("argument_stage")
        let commitField = settingsWindow.descendants(matching: .any)[
            "scholium.metadataSettings.commitField"
        ].firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) {
            commitField.exists && commitField.isEnabled
        })
        commitField.click()
        let saveMetadata = settingsWindow.buttons["Save Metadata Settings"]
        XCTAssertTrue(waitUntil(timeout: 5) {
            saveMetadata.exists && saveMetadata.isEnabled
        })
        saveMetadata.click()
        let settingsURL = triptychDirectory
            .appendingPathComponent(".scholium", isDirectory: true)
            .appendingPathComponent("settings.json")
        XCTAssertTrue(waitUntil(timeout: 10) {
            (try? String(contentsOf: settingsURL, encoding: .utf8))?
                .contains("argument_stage") == true
        })
        settingsWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !settingsWindow.exists })

        let secondMarker = "warm-custom-field-first-keystroke\n"
        try createAndType(
            path: "Untitled 2.md",
            initialSource: fixedYAML,
            marker: secondMarker
        )
        XCTAssertTrue(waitForDocumentTitle("Untitled 2", timeout: 20))

        app.menuBars.menuBarItems["Edit"].click()
        let editMetadata = app.menuItems["Edit Metadata…"].firstMatch
        XCTAssertTrue(editMetadata.waitForExistence(timeout: 3))
        editMetadata.click()
        let metadataEditor = app.descendants(matching: .any)[
            "scholium.metadataEditor"
        ].firstMatch
        XCTAssertTrue(metadataEditor.waitForExistence(timeout: 5))
        app.descendants(matching: .any)[
            "scholium.metadataEditor.addField"
        ].firstMatch.click()
        let chooserSearch = app.descendants(matching: .any)[
            "scholium.metadataChooser.search"
        ].firstMatch
        XCTAssertTrue(chooserSearch.waitForExistence(timeout: 5))
        chooserSearch.typeText("argument_stage")
        XCTAssertTrue(app.staticTexts["Argument Stage"].waitForExistence(timeout: 5))
        let chooserCancel = app.buttons.matching(
            NSPredicate(format: "label == %@", "Cancel")
        ).element(boundBy: 1)
        XCTAssertTrue(chooserCancel.waitForExistence(timeout: 5))
        chooserCancel.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !chooserSearch.exists })
        let closeMetadataEditor = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(closeMetadataEditor.waitForExistence(timeout: 5))
        closeMetadataEditor.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !metadataEditor.exists })
        let secondURL = triptychDirectory.appendingPathComponent(
            "01-analyses/Untitled 2.md"
        )
        XCTAssertTrue(waitUntil(timeout: 10) {
            (try? self.source(at: secondURL)) == fixedYAML + secondMarker
        })
    }


    @MainActor
    func testRetiredNavigationMenuIsAbsent() {
        XCTAssertFalse(app.menuBars.menuBarItems["Navigate"].exists)
        XCTAssertTrue(app.menuItems["Back"].exists)
        XCTAssertTrue(app.menuItems["Forward"].exists)
        XCTAssertFalse(app.menuItems["Recent Notes"].exists)
    }

    @MainActor
    func testPortableFolderPanelRejectsWrongExactFolderAndRecovers() throws {
        let wrongFolder = testDirectory.appendingPathComponent(
            "Wrong Portable Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: wrongFolder,
            withIntermediateDirectories: true
        )

        let appMenu = app.menuBars.menuBarItems["Scholium QA"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()

        let triptychsPane = app.descendants(matching: .any)["Triptychs"].firstMatch
        XCTAssertTrue(triptychsPane.waitForExistence(timeout: 10))
        triptychsPane.click()
        let settingsWindow = app.windows.matching(
            identifier: "com_apple_SwiftUI_Settings_window"
        ).firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        XCTAssertTrue(settingsWindow.descendants(matching: .any)[
            "scholium.portableControlAccess"
        ].waitForExistence(timeout: 5))

        authorizePortableFolder(wrongFolder, in: settingsWindow)
        let selectionError = settingsWindow.staticTexts[
            "Choose the folder containing Works shown above."
        ]
        XCTAssertTrue(selectionError.waitForExistence(timeout: 5))

        authorizePortableFolder(triptychDirectory, in: settingsWindow)
        XCTAssertTrue(waitUntil(timeout: 5) { !selectionError.exists })
    }

    @MainActor
    func testBootstrapFolderSelectionPresentsNativePanelAfterRootReplacement() throws {
        app.terminate()

        let cleanHome = testDirectory.appendingPathComponent(
            "file-selection-home",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: cleanHome,
            withIntermediateDirectories: true
        )

        app = XCUIApplication(bundleIdentifier: "com.scholium.qa")
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SCHOLIUM_HOME"] = cleanHome.path
        app.launchEnvironment["CFFIXED_USER_HOME"] = cleanHome.path
        app.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = UUID().uuidString
        app.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_PANEL_DIRECTORY"] = triptychDirectory.path
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10))
        getStarted.click()

        let connectExisting = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Connect Existing Folders")
        ).firstMatch
        XCTAssertTrue(connectExisting.waitForExistence(timeout: 5))
        connectExisting.click()
        app.buttons["Continue"].click()

        XCTAssertTrue(app.staticTexts["Choose Analyses"].waitForExistence(timeout: 5))
        let chooseFolder = app.buttons["Choose Folder…"]
        XCTAssertTrue(chooseFolder.waitForExistence(timeout: 5))
        chooseFolder.click()

        let panel = app.descendants(matching: .any)["open-panel"]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "Bootstrap must present one standard Open panel from its current native window."
        )
        XCTAssertFalse(app.staticTexts["File selection is unavailable in this window."].exists)
    }

    @MainActor
    func testRestoreAccessFolderSelectionUsesScenePresenter() {
        let restoreSheet = app.sheets.firstMatch
        XCTAssertTrue(
            restoreSheet.staticTexts["Restore Access"].waitForExistence(timeout: 8),
            "The isolated recovery route must present the real Restore Access sheet."
        )

        let chooseFolder = restoreSheet.buttons["Choose Folder…"]
        XCTAssertTrue(chooseFolder.waitForExistence(timeout: 5))
        chooseFolder.click()

        let panel = app.descendants(matching: .any)["open-panel"]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "Restore Access must present the shared native Open panel from its owning sheet."
        )
        XCTAssertFalse(
            restoreSheet.staticTexts[
                "File selection is unavailable in this window."
            ].exists
        )

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            restoreSheet.staticTexts["Restore Access"].exists,
            "Cancelling folder selection must leave Restore Access available for retry."
        )
    }

    @MainActor
    func testRestoreAccessQuitScholiumTerminatesApplication() {
        let restoreSheet = app.sheets.firstMatch
        XCTAssertTrue(
            restoreSheet.staticTexts["Restore Access"].waitForExistence(timeout: 8),
            "The isolated recovery route must present the real Restore Access sheet."
        )
        let quitScholium = restoreSheet.buttons["Quit Scholium"]
        XCTAssertTrue(quitScholium.waitForExistence(timeout: 5))
        quitScholium.click()

        XCTAssertTrue(
            waitUntil(timeout: 10) { self.app.state == .notRunning },
            "Quit Scholium must use the ordinary application termination path."
        )
    }

    @MainActor
    func testCleanAccountConfiguresAndRestoresACompleteTriptych() throws {
        app.terminate()
        XCTAssertTrue(
            waitUntil(timeout: 10) { self.app.state == .notRunning },
            "The fixture workspace must terminate before the clean-account launch."
        )

        let cleanHome = testDirectory.appendingPathComponent("clean-home", isDirectory: true)
        try FileManager.default.createDirectory(at: cleanHome, withIntermediateDirectories: true)

        app = XCUIApplication(bundleIdentifier: "com.scholium.qa")
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SCHOLIUM_HOME"] = cleanHome.path
        app.launchEnvironment["CFFIXED_USER_HOME"] = cleanHome.path
        app.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = UUID().uuidString
        app.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_PANEL_DIRECTORY"] = triptychDirectory.path
        app.launchEnvironment["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH"] = String(
            Int(QAWorkspaceMetricContract.preferredWidth)
        )
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        let setupSurfaces = app.descendants(matching: .any)
            .matching(identifier: "scholium.bootstrap")
        let setup = setupSurfaces.firstMatch
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        XCTAssertEqual(
            app.windows.count,
            1,
            "First launch must present one setup surface, not root setup plus a duplicate sheet."
        )
        XCTAssertTrue(app.staticTexts["Scholium"].exists)
        let setupFrame = app.windows.firstMatch.frame
        XCTAssertEqual(
            setupFrame.width,
            QABootstrapMetricContract.preferredWidth,
            accuracy: QAWorkspaceMetricContract.frameTolerance,
            "Bootstrap's 720pt contract is an initial size, not a minimum."
        )
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        XCTAssertFalse(app.splitGroups["scholium.workspaceSplitView"].exists)
        XCTAssertFalse(app.buttons["Show Sidebar"].exists)
        XCTAssertFalse(app.buttons["Hide Sidebar"].exists)
        XCTAssertFalse(app.buttons["Show Research Inspector"].exists)
        XCTAssertFalse(app.buttons["Hide Research Inspector"].exists)

        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.click()
        XCTAssertTrue(app.staticTexts["Choose a Starting Point"].waitForExistence(timeout: 5))
        let connectExisting = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Connect Existing Folders")
        ).firstMatch
        XCTAssertTrue(connectExisting.waitForExistence(timeout: 5))
        connectExisting.click()
        app.buttons["Continue"].click()
        XCTAssertTrue(app.staticTexts["Choose Analyses"].waitForExistence(timeout: 3))

        let analyses = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let topics = triptychDirectory.appendingPathComponent("02-topics", isDirectory: true)
        let works = triptychDirectory.appendingPathComponent("03-works", isDirectory: true)
        chooseSetupFolder(analyses, role: "Analyses")
        app.buttons["Continue"].click()

        XCTAssertTrue(app.staticTexts["Choose Topics"].waitForExistence(timeout: 3))
        chooseSetupFolder(topics, role: "Topics")
        app.buttons["Continue"].click()

        XCTAssertTrue(app.staticTexts["Choose Works"].waitForExistence(timeout: 3))
        chooseSetupFolder(works, role: "Works")
        app.buttons["Continue"].click()

        XCTAssertTrue(app.staticTexts["Authorize the Detected Folder"].waitForExistence(timeout: 5))
        authorizePortableFolder(triptychDirectory)
        XCTAssertTrue(app.staticTexts["Review the Connected Triptych"].waitForExistence(timeout: 5))
        let complete = app.buttons["Use This Triptych"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        XCTAssertTrue(complete.isEnabled)
        complete.click()

        XCTAssertTrue(app.staticTexts["Prepare an Agent"].waitForExistence(timeout: 10))
        let setUpLater = app.buttons["Set Up Later"]
        XCTAssertTrue(setUpLater.waitForExistence(timeout: 5))
        setUpLater.click()
        XCTAssertTrue(app.staticTexts["Your Triptych Is Ready"].waitForExistence(timeout: 30))
        let openWorkspace = app.buttons["Open Workspace"]
        XCTAssertTrue(openWorkspace.waitForExistence(timeout: 5))
        openWorkspace.click()

        let analysesControl = app.buttons["Analyses"]
        let librarySurface = app.descendants(matching: .any)["scholium.librarySurface"]
        let loadingOverlay = app.descendants(matching: .any)["scholium.loadingOverlay"]
        XCTAssertTrue(waitUntil(timeout: 45) {
            analysesControl.exists && librarySurface.exists && !loadingOverlay.exists
        }, "Completing first-run setup must finish opening the Triptych and dismiss loading.")
        XCTAssertTrue(waitUntil(timeout: 10) {
            self.app.windows.count == 1
                && !self.app.descendants(matching: .any)["scholium.bootstrap"].exists
                && self.app.splitGroups["scholium.workspaceSplitView"].exists
        }, "Successful setup must replace Bootstrap with one configured workspace window.")
        let workspaceWindow = app.windows.firstMatch
        if let visibleScreenWidth = NSScreen.main?.visibleFrame.width,
           visibleScreenWidth >= QAWorkspaceMetricContract.preferredWidth {
            XCTAssertTrue(waitUntil(timeout: 5) {
                abs(
                    workspaceWindow.frame.width
                        - QAWorkspaceMetricContract.preferredWidth
                ) <= QAWorkspaceMetricContract.frameTolerance
            })
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.75))
        let workspaceFrame = workspaceWindow.frame
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.triptychSetup"].exists,
            "Completing first-run setup must close Bootstrap instead of presenting it over the workspace."
        )
        let analysisRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
        XCTAssertTrue(analysisRow.waitForExistence(timeout: 15))
        analysisRow.click()
        waitForCurrentDocumentSurface()
        XCTAssertEqual(workspaceWindow.frame, workspaceFrame)

        XCTAssertEqual(workspaceWindow.frame, workspaceFrame)

        let manifest = triptychDirectory.appendingPathComponent(".scholium/manifest.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: manifest.path),
            "Expected setup to create only its portable control manifest beside Works."
        )

        app.terminate()
        app = XCUIApplication(bundleIdentifier: "com.scholium.qa")
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SCHOLIUM_HOME"] = cleanHome.path
        app.launchEnvironment["CFFIXED_USER_HOME"] = cleanHome.path
        app.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Analyses"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)["scholium.triptychSetup"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
                .waitForExistence(timeout: 15)
        )

        let appMenu = app.menuBars.menuBarItems["Scholium QA"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()
        let triptychsPane = app.descendants(matching: .any)["Triptychs"].firstMatch
        XCTAssertTrue(triptychsPane.waitForExistence(timeout: 10))
        triptychsPane.click()
        let nameField = app.descendants(matching: .any)["scholium.triptychName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        try paste("QA Renamed Triptych", into: nameField)
        let saveTriptych = app.buttons["Save Triptych"]
        XCTAssertTrue(saveTriptych.waitForExistence(timeout: 5))
        XCTAssertTrue(saveTriptych.isEnabled)
        saveTriptych.click()
        XCTAssertTrue(waitUntil(timeout: 10) {
            !self.app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "manifest.json")
            ).firstMatch.exists
        })
        let registryURL = cleanHome
            .appendingPathComponent("ApplicationSupport/Workspace/workspace-registration-v3.json")
        XCTAssertTrue(waitUntil(timeout: 10) {
            (try? String(contentsOf: registryURL, encoding: .utf8))?
                .contains("QA Renamed Triptych") == true
        })
    }


    @MainActor
    func testSettingsFixedColumnsKeepDetailInsideItsPlane() throws {
        let appMenu = app.menuBars.menuBarItems["Scholium QA"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()

        let settingsWindow = app.windows.matching(
            identifier: "com_apple_SwiftUI_Settings_window"
        ).firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 8))
        let triptychsDestination = settingsWindow.descendants(matching: .any)[
            "scholium.settings.destination.triptychs"
        ]
        XCTAssertTrue(triptychsDestination.waitForExistence(timeout: 8))
        triptychsDestination.click()
        let sidebar = settingsWindow.descendants(matching: .any)[
            "scholium.settings.sidebar"
        ].firstMatch
        let detail = settingsWindow.descendants(matching: .any)[
            "scholium.triptychSetup"
        ].firstMatch
        let search = settingsWindow.searchFields.firstMatch
        let newTriptych = settingsWindow.buttons["New Triptych…"]
        let saveTriptych = settingsWindow.buttons["Save Triptych"]

        for element in [sidebar, detail, search, newTriptych, saveTriptych] {
            XCTAssertTrue(element.waitForExistence(timeout: 8))
        }

        XCTAssertLessThanOrEqual(search.frame.maxX, sidebar.frame.maxX)
        XCTAssertGreaterThanOrEqual(detail.frame.minX, sidebar.frame.maxX)
        XCTAssertLessThanOrEqual(
            newTriptych.frame.maxX,
            settingsWindow.frame.maxX - 19
        )
        XCTAssertLessThanOrEqual(
            saveTriptych.frame.maxX,
            settingsWindow.frame.maxX,
            "The Triptych save action must remain inside the Settings window."
        )

        let screenshot = XCTAttachment(screenshot: settingsWindow.screenshot())
        screenshot.name = "Settings fixed column surfaces"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testSettingsUsesCanonicalPanesScopesAndGuidanceCategories() throws {
        let appMenu = app.menuBars.menuBarItems["Scholium QA"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()

        let settingsRoot = app.descendants(matching: .any)["scholium.settings.root"]
        XCTAssertTrue(settingsRoot.waitForExistence(timeout: 10))
        let paneNames = [
            "Triptychs",
            "Appearance",
            "Hotkeys",
            "Metadata",
            "Attention",
            "Skills",
            "Action Profiles",
            "Agent Access",
            "External Tools & Citations",
        ]
        for paneName in paneNames {
            XCTAssertTrue(
                app.descendants(matching: .any)[paneName].firstMatch.exists,
                "Missing canonical Settings pane: \(paneName)"
            )
        }

        app.descendants(matching: .any)[
            "scholium.settings.destination.triptychs"
        ].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.settings.triptychScope"
        ].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.triptychName"
        ].waitForExistence(timeout: 8))

        app.descendants(matching: .any)[
            "scholium.settings.destination.metadata"
        ].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            !self.app.descendants(matching: .any)[
                "scholium.settings.triptychScope"
            ].exists
        })
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.metadataSettings.role"
        ].waitForExistence(timeout: 8))

        app.descendants(matching: .any)[
            "scholium.settings.destination.appearance"
        ].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.appearance.form"
        ].waitForExistence(timeout: 8))

        app.descendants(matching: .any)[
            "scholium.settings.destination.hotkeys"
        ].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.hotkeys.command.searchResearch"
        ].waitForExistence(timeout: 8))

        app.descendants(matching: .any)[
            "scholium.settings.destination.attention"
        ].firstMatch.click()
        XCTAssertTrue(app.staticTexts[
            "Reminder Timing for This Triptych"
        ].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Dismissed Items on This Mac"].exists)

        XCTAssertFalse(app.staticTexts["Researcher Skills"].exists)
        XCTAssertFalse(app.staticTexts["Permissions"].exists)

        app.descendants(matching: .any)[
            "scholium.settings.destination.skills"
        ].firstMatch.click()
        for actionID in [
            "discuss", "analyze", "synthesize", "write", "critique",
            "check-fidelity",
        ] {
            XCTAssertTrue(app.descendants(matching: .any)[
                "scholium.researchGuidance.skill.\(actionID)"
            ].waitForExistence(timeout: 8))
        }

        app.descendants(matching: .any)[
            "scholium.settings.destination.actionProfiles"
        ].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchGuidance.profile.analyze.enabled"
        ].waitForExistence(timeout: 20))
        XCTAssertFalse(app.menuButtons["Add Skill"].exists)

        app.descendants(matching: .any)[
            "scholium.settings.destination.externalToolsCitations"
        ].firstMatch.click()
        XCTAssertTrue(app.staticTexts[
            "External Tools & Citations"
        ].waitForExistence(timeout: 20))
        let externalTools = app.scrollViews[
            "scholium.researchGuidance.detail"
        ].firstMatch
        XCTAssertTrue(externalTools.waitForExistence(timeout: 8))
        let copyCLIInstructions = app.buttons[
            "scholium.agentCLI.copyInstructions"
        ]
        for _ in 0..<8 where !copyCLIInstructions.exists {
            externalTools.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(copyCLIInstructions.waitForExistence(timeout: 8))

        XCTAssertFalse(app.buttons["Reveal Skills Folder"].exists)
        XCTAssertFalse(app.buttons["Reveal Legacy Data"].exists)
    }
















    @MainActor
    func testCritiqueFindingOpensExactWorkPassageInSource() throws {
        waitForCurrentDocumentSurface()
        selectVault(
            "scholium.vault.output",
            waitingFor: "scholium.folderRow.Critiques"
        )

        let critiquesFolder = app.buttons["Critiques"].firstMatch
        XCTAssertTrue(critiquesFolder.waitForExistence(timeout: 8))
        critiquesFolder.click()

        let critiqueRow = app.descendants(matching: .any)[
            "scholium.noteRow.Critiques/QA Critique.md"
        ]
        XCTAssertTrue(critiqueRow.waitForExistence(timeout: 8))
        critiqueRow.click()

        let provenance = app.descendants(matching: .any)["scholium.critiqueProvenance"]
        XCTAssertTrue(provenance.waitForExistence(timeout: 8))
        let agentAttribution = provenance.staticTexts
            .matching(NSPredicate(format: "value CONTAINS %@", "Agent-authored Critique"))
            .firstMatch
        XCTAssertTrue(agentAttribution.waitForExistence(timeout: 3))

        let findings = provenance.descendants(matching: .any)["scholium.critiqueFindings"]
        XCTAssertTrue(findings.waitForExistence(timeout: 5))
        findings.click()

        let finding = app.buttons["Traced: Topic connection"].firstMatch
        XCTAssertTrue(finding.waitForExistence(timeout: 5))
        XCTAssertTrue(finding.isEnabled)
        XCTAssertTrue(
            accessibilityText(of: finding).contains("Line")
                || accessibilityText(of: finding).contains("Heading"),
            "The finding must expose the exact recorded passage destination before navigation."
        )
        finding.click()

        XCTAssertTrue(waitForDocumentTitle("QA Work", timeout: 8))
        let sourceEditor = app.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 8))
        let workURL = triptychDirectory.appendingPathComponent(
            "03-works/QA Work.md"
        )
        XCTAssertTrue(try source(at: workURL).contains("[[QA Topic]]"))
        let mode = documentModeControl()
        XCTAssertEqual(mode.value as? String, "Source")
    }

    @MainActor
    func testDocumentModesInspectorAndSearchAreKeyboardReachable() throws {
        let mode = documentModeControl()
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["View"].click()
        let documentModeMenu = app.menuItems["Document Mode"].firstMatch
        XCTAssertTrue(documentModeMenu.waitForExistence(timeout: 3))
        documentModeMenu.hover()
        XCTAssertTrue(app.menuItems["Edit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Source"].exists)
        app.typeKey(.escape, modifierFlags: [])

        selectDocumentMode("Edit")
        selectDocumentMode("Review")

        let inspector = inspectorVisibilityControl()
        XCTAssertTrue(inspector.exists)

        app.typeKey("f", modifierFlags: [.command, .shift])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
    }


    @MainActor
    func testReviewOwnsFootnoteNavigationAndEditKeepsItPassive() throws {
        selectDocumentMode("Review")
        let reference = app.buttons["Footnote 1"].firstMatch
        XCTAssertTrue(reference.waitForExistence(timeout: 8))
        let renderedDocument = app.descendants(matching: .any)["Rendered Markdown"]
        renderedDocument.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        for _ in 0..<16 where !reference.isHittable {
            app.typeKey(.pageDown, modifierFlags: [])
        }
        XCTAssertTrue(reference.isHittable)
        reference.click()

        let returnToReference = app.buttons["Return to footnote reference 1"].firstMatch
        XCTAssertTrue(returnToReference.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { returnToReference.isHittable })
        returnToReference.click()
        let referenceFocus = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: reference
        )
        XCTAssertEqual(XCTWaiter.wait(for: [referenceFocus], timeout: 5), .completed)

        let mode = documentModeControl()
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        selectDocumentMode("Edit")
        XCTAssertTrue(
            app.descendants(matching: .any)["Markdown editor, Edit mode"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertFalse(app.buttons["Footnote 1"].exists)
        XCTAssertFalse(app.buttons["Return to footnote reference 1"].exists)

        selectDocumentMode("Source")
        XCTAssertTrue(app.descendants(matching: .any)["Markdown source editor"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Footnote 1"].exists)
        XCTAssertFalse(app.buttons["Return to footnote reference 1"].exists)
    }


    @MainActor
    func testSearchThisNoteReportsMatchesNoResultsAndCloses() throws {
        selectDocumentMode("Review")
        let renderedDocument = app.descendants(matching: .any)["Rendered Markdown"]
        XCTAssertTrue(waitUntil(timeout: 20) { renderedDocument.exists })

        app.typeKey("f", modifierFlags: [.command, .shift])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        let field = app.descendants(matching: .any)["scholium.searchField"]
        let result = searchResult(named: "QA Autosave A")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let searchMode = app.descendants(matching: .any)["scholium.searchMode"]
        let closeSearch = app.descendants(matching: .any)["scholium.closeSearchButton"]
        XCTAssertTrue(searchMode.waitForExistence(timeout: 5))
        XCTAssertTrue(closeSearch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["scholium.searchScope.thisNote"].exists)
        XCTAssertTrue(app.buttons["scholium.searchScope.currentVault"].exists)
        XCTAssertTrue(app.buttons["scholium.searchScope.triptych"].exists)
        let collapsedControls = field.frame
            .union(searchMode.frame)
            .union(closeSearch.frame)
        XCTAssertLessThanOrEqual(collapsedControls.width, 644)
        XCTAssertLessThanOrEqual(collapsedControls.height, 80)

        app.buttons["scholium.searchScope.thisNote"].click()
        typeCommittedText("analysis", into: field, in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        let expandedContentHeight = result.frame.maxY - field.frame.minY
        XCTAssertGreaterThan(expandedContentHeight, collapsedControls.height)
        XCTAssertLessThanOrEqual(expandedContentHeight, 524)

        typeCommittedText("qa-no-search-match-94731", into: field, in: app)
        XCTAssertTrue(waitUntil(timeout: 5) {
            !result.exists
        })
        XCTAssertTrue(
            waitUntil(timeout: 5) { closeSearch.exists },
            "A new query must not dismiss Search by opening a stale result."
        )

        closeSearch.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })
        XCTAssertTrue(renderedDocument.exists)
    }

    @MainActor
    func testSearchOpensTheSelectedResultFromTheKeyboard() throws {
        waitForCurrentDocumentSurface()

        app.typeKey("f", modifierFlags: [.command, .shift])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        let field = app.descendants(matching: .any)["scholium.searchField"]
        let result = searchResult(named: "QA Autosave A")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let thisNote = app.buttons["scholium.searchScope.thisNote"]
        XCTAssertTrue(thisNote.waitForExistence(timeout: 5))
        thisNote.click()
        typeCommittedText("analysis", into: field, in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        field.click()
        field.typeKey(.downArrow, modifierFlags: [])

        let selectionAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        selectionAttachment.name = "Search editorial selection"
        selectionAttachment.lifetime = .keepAlways
        add(selectionAttachment)

        field.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(waitUntil(timeout: 5) { !search.exists })
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 5))
        let sourceEditor = app.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(
            sourceEditor.waitForExistence(timeout: 10),
            "The selected Search result did not finish revealing its source range."
        )
        let mode = documentModeControl()
        XCTAssertEqual(mode.value as? String, "Source")
    }

    @MainActor
    func testSearchQueriesExplicitDirectRelationsWithoutParallelResults() throws {
        waitForCurrentDocumentSurface()

        app.typeKey("f", modifierFlags: [.command, .shift])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        let field = app.descendants(matching: .any)["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let triptych = app.buttons["scholium.searchScope.triptych"]
        XCTAssertTrue(triptych.waitForExistence(timeout: 5))
        triptych.click()
        typeCommittedText(
            "from-note:\"QA Direct Relation Concept 947\" relation:supports",
            into: field,
            in: app
        )

        let relatedAnalysis = searchResult(named: "QA Autosave A")
        XCTAssertTrue(relatedAnalysis.waitForExistence(timeout: 10))
        XCTAssertFalse(searchResult(named: "QA Direct Relation Topic").exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "value CONTAINS[c] %@",
            "directly supported"
        )).firstMatch.exists)

        let resultScroll = app.outlines["scholium.searchResults"].firstMatch
        XCTAssertTrue(resultScroll.waitForExistence(timeout: 5))
        if !relatedAnalysis.isHittable {
            scrollUntilHittable(relatedAnalysis, in: resultScroll)
        }
        relatedAnalysis.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !search.exists })
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 5))
    }

    @MainActor
    func testSearchExplainsTitleAliasHeadingAndBodyRanking() throws {
        waitForCurrentDocumentSurface()

        app.typeKey("f", modifierFlags: [.command, .shift])
        let field = app.descendants(matching: .any)["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let triptych = app.buttons["scholium.searchScope.triptych"]
        XCTAssertTrue(triptych.waitForExistence(timeout: 5))
        triptych.click()
        typeCommittedText("deliberative autonomy", into: field, in: app)

        let title = searchResult(named: "Deliberative Autonomy")
        let alias = searchResult(named: "Agency Structure")
        let heading = searchResult(named: "Normative Architecture")
        let body = searchResult(named: "Practical Reason")
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(alias.waitForExistence(timeout: 10))
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertTrue(body.waitForExistence(timeout: 10))

        XCTAssertTrue(title.label.contains(", Title,"))
        XCTAssertTrue(alias.label.contains(", Alias,"))
        XCTAssertTrue(heading.label.contains(", Heading,"))
        XCTAssertTrue(body.label.contains(", Body,"))
        XCTAssertLessThan(title.frame.minY, alias.frame.minY)
        XCTAssertLessThan(alias.frame.minY, heading.frame.minY)
        XCTAssertLessThan(heading.frame.minY, body.frame.minY)
    }



}
