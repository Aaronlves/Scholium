@preconcurrency import XCTest
import AppKit
import CryptoKit
import notify

extension ScholiumUITests {
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
            "scholium.folderRow.Cluster-10"
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
            "01-analyses/Cluster-10/QA Autosave B.md"
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
            "scholium.noteRow.Cluster-10/QA Autosave B.md"
        ].firstMatch
        XCTAssertTrue(
            destination.waitForExistence(timeout: 5),
            "The committed move did not publish its destination row immediately."
        )
        XCTAssertFalse(source.exists)
        XCTAssertTrue(waitUntil(timeout: 5) {
            FileManager.default.fileExists(atPath: destinationURL.path)
                && !FileManager.default.fileExists(atPath: sourceURL.path)
        })
        let documentTitle = app.staticTexts["scholium.documentNoteName"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) {
            (documentTitle.value as? String) == "QA Autosave B"
        })
    }

    /// The fixed LocationHeader—not unoccupied outline space or a root Note
    /// row—is the native pointer target for moving an item back to the vault
    /// root. The source-ahead projection must publish that root row at commit.
    @MainActor
    func testNativeLocationHeaderDropMovesNoteToVaultRoot() throws {
        let noteList = app.descendants(matching: .any)[
            "scholium.noteList"
        ].firstMatch
        let folder = app.descendants(matching: .any)[
            "scholium.folderRow.Cluster-01"
        ].firstMatch
        let locationHeader = app.descendants(matching: .any)[
            "scholium.locationPicker"
        ].firstMatch
        XCTAssertTrue(noteList.waitForExistence(timeout: 10))
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        XCTAssertTrue(locationHeader.waitForExistence(timeout: 5))

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
        XCTAssertTrue(locationHeader.isHittable)

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
                thenDragTo: locationHeader.coordinate(
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
            "The LocationHeader drop did not publish the root Note row."
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
    func testCanonicalAcceptanceJourney() throws {
        let renderedDocument = app.descendants(matching: .any)["Rendered Markdown"]
        let documentTabs = app.descendants(matching: .any)["scholium.documentTabs"]
        let documentTitle = app.staticTexts["scholium.documentNoteName"].firstMatch
        let inspectorButton = app.descendants(matching: .any)["scholium.toggleInspector"]
        let inspector = app.scrollViews["scholium.researchInspector"]
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]

        XCTAssertTrue(waitUntil(timeout: 20) { renderedDocument.exists })
        XCTAssertFalse(documentTabs.exists)
        XCTAssertTrue(documentTitle.waitForExistence(timeout: 10))
        XCTAssertEqual(documentTitle.value as? String, "QA Autosave A")
        XCTAssertTrue(inspectorButton.exists)

        XCTContext.runActivity(named: "Peripheral controls use the native pointer path") { _ in
            exercisePeripheralVisibilityControls()
        }

        XCTContext.runActivity(named: "Search, properties, and inspector") { _ in
            app.typeKey("f", modifierFlags: [.command])
            let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
            let field = app.descendants(matching: .any)["scholium.searchField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            typeCommittedText("Autosave", into: field, in: app)
            let result = app.descendants(matching: .any)["scholium.searchResult.QA Autosave A.md"]
            XCTAssertTrue(result.waitForExistence(timeout: 8))
            app.buttons["Close"].click()
            XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })

            app.menuBars.menuBarItems["Edit"].click()
            let editProperties = app.menuItems["Edit Properties…"].firstMatch
            XCTAssertTrue(editProperties.waitForExistence(timeout: 3))
            editProperties.click()
            let properties = app.descendants(matching: .any)["scholium.propertiesEditor"]
            XCTAssertTrue(properties.waitForExistence(timeout: 5))
            app.buttons["Cancel"].click()
            XCTAssertTrue(waitUntil(timeout: 3) { !properties.exists })

            inspectorButton.click()
            XCTAssertTrue(inspector.waitForExistence(timeout: 3))
            inspectorButton.click()
            XCTAssertTrue(waitUntil(timeout: 3) { !inspector.exists })
        }

        XCTContext.runActivity(named: "Actions keeps role-valid work and Settle explicit") { _ in
            selectResearchInspectorMode("actions")
            XCTAssertTrue(app.descendants(matching: .any)[
                "scholium.researchAction.discuss"
            ].waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)[
                "scholium.researchAction.settle"
            ].exists)
            XCTAssertFalse(app.buttons["Complete Review"].exists)
            XCTAssertFalse(app.staticTexts["Research Activity"].exists)
            XCTAssertFalse(app.buttons["Open Research Record"].exists)

            let discuss = app.descendants(matching: .any)[
                "scholium.researchAction.discuss"
            ]
            XCTAssertTrue(discuss.exists)
            discuss.click()
            XCTAssertTrue(app.descendants(matching: .any)[
                "scholium.researchAction.sheet"
            ].waitForExistence(timeout: 5))
            app.typeKey(.escape, modifierFlags: [])
        }

        XCTContext.runActivity(named: "Peer vaults keep explicit Library selection") { _ in
            let analyses = app.buttons["scholium.vault.paper_analysis"].firstMatch
            let topics = app.buttons["scholium.vault.topic_knowledge"].firstMatch
            XCTAssertTrue(analyses.exists)
            XCTAssertTrue(topics.exists)

            topics.click()
            let topicRow = app.descendants(matching: .any)["scholium.noteRow.QA Topic.md"]
            XCTAssertTrue(topicRow.waitForExistence(timeout: 8))
            XCTAssertEqual(documentTitle.value as? String, "QA Autosave A")
            topicRow.click()
            XCTAssertTrue(waitUntil(timeout: 8) {
                (documentTitle.value as? String) == "QA Topic"
            })

            analyses.click()
            let analysisRow = app.descendants(matching: .any)[
                "scholium.noteRow.QA Autosave A.md"
            ]
            XCTAssertTrue(analysisRow.waitForExistence(timeout: 8))
            XCTAssertEqual(documentTitle.value as? String, "QA Topic")
            analysisRow.click()
            XCTAssertTrue(waitUntil(timeout: 8) {
                (documentTitle.value as? String) == "QA Autosave A"
            })

            topics.click()
            XCTAssertTrue(topicRow.waitForExistence(timeout: 8))
            XCTAssertEqual(documentTitle.value as? String, "QA Autosave A")
            topicRow.click()
            XCTAssertTrue(waitUntil(timeout: 8) {
                (documentTitle.value as? String) == "QA Topic"
            })
        }

        XCTContext.runActivity(named: "Overview exposes exact Analysis Zotero navigation") { _ in
            let analyses = app.buttons["scholium.vault.paper_analysis"].firstMatch
            analyses.click()
            let analysisRow = app.descendants(matching: .any)[
                "scholium.noteRow.QA Autosave A.md"
            ]
            XCTAssertTrue(analysisRow.waitForExistence(timeout: 8))
            analysisRow.click()
            XCTAssertTrue(waitUntil(timeout: 8) {
                (documentTitle.value as? String) == "QA Autosave A"
            })

            if !inspector.exists {
                inspectorButton.click()
                XCTAssertTrue(inspector.waitForExistence(timeout: 3))
            }
            selectResearchInspectorMode("overview")
            let openInZotero = app.descendants(matching: .any)[
                "scholium.researchOverview.openInZotero"
            ]
            XCTAssertTrue(openInZotero.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["QAITEM01"].exists)
            XCTAssertFalse(app.buttons["Open PDF in Preview"].exists)
            XCTAssertFalse(app.buttons["Open Attachment"].exists)
        }

        XCTContext.runActivity(named: "Live Preview projects the document and commits before navigation") { _ in
            XCTAssertTrue(mode.exists)
            mode.click()
            let livePreview = app.menuItems
                .matching(identifier: "text.page.badge.magnifyingglass")
                .firstMatch
            XCTAssertTrue(livePreview.waitForExistence(timeout: 3))
            livePreview.click()

            let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
            XCTAssertTrue(editor.waitForExistence(timeout: 8))
            // WebKit exposes CodeMirror's lossless source buffer through
            // AXValue even when the live-preview decorations hide frontmatter
            // from the rendered surface. The projection itself is covered by
            // the editor bundle/style contract; this journey verifies that the
            // projected editor remains interactive and commits its source.
            XCTAssertFalse((editor.value as? String ?? "").isEmpty)

            let token = " ACCEPTANCE-\(UUID().uuidString)"
            let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
            editor.click()
            editor.typeKey(.end, modifierFlags: [.command])
            editor.typeText(token)
            XCTAssertFalse((try? source(at: noteURL).contains(token)) ?? true)

            app.typeKey("f", modifierFlags: [.command, .shift])
            let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
            XCTAssertTrue(search.waitForExistence(timeout: 8))
            XCTAssertTrue(waitUntil(timeout: 8) { (try? self.source(at: noteURL).contains(token)) == true })
            app.buttons["Close"].click()
            XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })
        }

        XCTContext.runActivity(named: "An independent second window remains reachable") { _ in
            let productWindows = app.windows.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "scholium-")
            )
            let initialProductWindowCount = productWindows.count
            app.typeKey("n", modifierFlags: [.command])
            XCTAssertTrue(waitUntil(timeout: 8) {
                productWindows.count > initialProductWindowCount
            })
        }
    }

    /// D-104 has no temporary or implicit read-only fallback. This journey
    /// starts the real QA composition with an unusable explicit storage root,
    /// proves that only the recovery surface is reachable, then repairs the
    /// root and invokes the default Retry keyboard action before a Workspace
    /// is allowed to appear.
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
            waitUntil(timeout: 90) { renderedDocument.exists },
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
        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))

        app.typeKey("f", modifierFlags: [.command, .shift])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))

        let field = app.descendants(matching: .any)["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let triptych = app.radioButtons["Triptych"]
        XCTAssertTrue(triptych.waitForExistence(timeout: 5))
        triptych.click()
        typeCommittedText("Normative QA Nexus", into: field, in: app)

        let result = app.descendants(matching: .any)["scholium.searchResult.QA Topic.md"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.click()

        XCTAssertTrue(waitUntil(timeout: 8) {
            (metadata.value as? String) == "QA Topic"
        })
        XCTAssertTrue(app.buttons["scholium.vault.topic_knowledge"].exists)
        XCTAssertFalse(search.exists)
    }

    @MainActor
    func testNewAnalysisCreationHasNoPropertyRequirements() throws {
        let libraryFilters = app.descendants(matching: .any)[
            "scholium.libraryFilters"
        ]
        XCTAssertTrue(libraryFilters.waitForExistence(timeout: 10))
        libraryFilters.click()
        let connectionFilter = app.menuItems["Explicit Connections"].firstMatch
        XCTAssertTrue(connectionFilter.waitForExistence(timeout: 5))
        XCTAssertTrue(connectionFilter.isEnabled)
        connectionFilter.click()
        let filterStatus = app.descendants(matching: .any)[
            "scholium.libraryFilterStatus"
        ]
        XCTAssertTrue(filterStatus.waitForExistence(timeout: 5))

        let libraryCreate = app.descendants(matching: .any)["scholium.libraryCreate"]
        XCTAssertTrue(libraryCreate.waitForExistence(timeout: 10))
        libraryCreate.click()
        let newNote = app.descendants(matching: .any)["scholium.newNote"]
        let newFolder = app.descendants(matching: .any)["scholium.newFolder"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 3))
        XCTAssertTrue(newFolder.exists)
        newNote.click()

        XCTAssertFalse(
            app.buttons["Create"].firstMatch.waitForExistence(timeout: 1),
            "Direct note creation must not present the retired lifecycle sheet."
        )
        XCTAssertFalse(app.buttons["Declare Now"].exists)
        XCTAssertFalse(app.radioButtons["Declare Now"].exists)
        XCTAssertFalse(app.radioButtons["Not Yet"].exists)
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.newNote.researchUnitCompletion"
        ].exists)
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.newNote.researchUnitScope"
        ].exists)
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.newNote.researchUnitLimitations"
        ].exists)

        let createdURL = triptychDirectory.appendingPathComponent("01-analyses/Untitled.md")
        XCTAssertTrue(waitUntil(timeout: 10) { FileManager.default.fileExists(atPath: createdURL.path) })
        let source = try source(at: createdURL)
        XCTAssertEqual(source, "")
        XCTAssertFalse(source.contains("research_unit"))

        XCTAssertTrue(waitUntil(timeout: 10) {
            !filterStatus.exists
                && (libraryFilters.value as? String) == "No filters active"
        })
        let createdRow = app.descendants(matching: .any)[
            "scholium.noteRow.Untitled.md"
        ]
        XCTAssertTrue(createdRow.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 5) { createdRow.isSelected })
        let createdTitle = app.descendants(matching: .any)[
            "scholium.documentNoteName"
        ]
        XCTAssertTrue(waitUntil(timeout: 20) {
            createdTitle.value as? String == "Untitled"
        })
    }

    @MainActor
    func testMissingAnalysisPropertiesAreOmittedFromAbout() throws {
        let libraryCreate = app.descendants(matching: .any)["scholium.libraryCreate"]
        XCTAssertTrue(libraryCreate.waitForExistence(timeout: 10))
        libraryCreate.click()
        let newNote = app.descendants(matching: .any)["scholium.newNote"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 3))
        newNote.click()

        XCTAssertFalse(
            app.buttons["Create"].firstMatch.waitForExistence(timeout: 1),
            "Direct note creation must not present a naming or Properties sheet."
        )

        let createdURL = triptychDirectory.appendingPathComponent(
            "01-analyses/Untitled.md"
        )
        XCTAssertTrue(waitUntil(timeout: 10) {
            FileManager.default.fileExists(atPath: createdURL.path)
        })
        let createdSource = try source(at: createdURL)
        XCTAssertEqual(createdSource, "")
        XCTAssertFalse(createdSource.contains("research_unit"))

        let createdTitle = app.descendants(matching: .any)[
            "scholium.documentNoteName"
        ]
        XCTAssertTrue(waitUntil(timeout: 45) {
            createdTitle.value as? String == "Untitled"
        })
        let emptyReview = app.descendants(matching: .any)[
            "scholium.emptyNoteReview"
        ]
        XCTAssertTrue(
            emptyReview.waitForExistence(timeout: 5),
            "An exact empty note must present its completed Review state immediately."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.renderedDocument.loading"].exists
        )

        selectResearchInspectorMode("overview")
        let about = app.descendants(matching: .any)["scholium.about"]
        XCTAssertTrue(about.waitForExistence(timeout: 8))
        for omittedField in [
            "Completion", "Limitations", "Authors", "Year", "Type", "Source Basis",
        ] {
            XCTAssertFalse(about.staticTexts[omittedField].exists)
        }
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.reviewResearchStatusGate"
        ].exists)
        XCTAssertFalse(app.buttons["Complete Review"].exists)
    }

    @MainActor
    func testFolderContextMenuCreatesInsideFolderAndExposesLifecycleActions() throws {
        let folderRow = app.descendants(matching: .any)[
            "scholium.folderRow.Cluster-01"
        ]
        XCTAssertTrue(folderRow.waitForExistence(timeout: 10))
        folderRow.rightClick()

        let folderMenu = app.menus["scholium.folderRow.Cluster-01"]
        XCTAssertTrue(folderMenu.waitForExistence(timeout: 3))
        let newNote = folderMenu.menuItems["New Note"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 3))
        let newFolder = folderMenu.menuItems["New Folder"]
        XCTAssertTrue(newFolder.exists)
        XCTAssertTrue(folderMenu.menuItems["Rename Folder…"].exists)
        XCTAssertTrue(folderMenu.menuItems["Move Folder…"].exists)
        XCTAssertTrue(
            folderMenu.menuItems["Expand All"].exists
                || folderMenu.menuItems["Collapse All"].exists
        )
        XCTAssertTrue(folderMenu.menuItems["Copy Relative Path"].exists)
        XCTAssertTrue(folderMenu.menuItems["Reveal in Finder"].exists)
        XCTAssertTrue(folderMenu.menuItems["Move Folder and Notes to Trash…"].exists)
        newFolder.click()

        XCTAssertFalse(
            app.textFields["scholium.folderName"].waitForExistence(timeout: 1),
            "Direct folder creation must not present a naming sheet."
        )
        let createdFolderURL = triptychDirectory.appendingPathComponent(
            "01-analyses/Cluster-01/Untitled Folder",
            isDirectory: true
        )
        XCTAssertTrue(waitUntil(timeout: 10) {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(
                atPath: createdFolderURL.path,
                isDirectory: &isDirectory
            ) && isDirectory.boolValue
        })
        let createdFolderRow = app.descendants(matching: .any)[
            "scholium.folderRow.Cluster-01/Untitled Folder"
        ]
        XCTAssertTrue(createdFolderRow.waitForExistence(timeout: 10))

        createdFolderRow.rightClick()
        let createdFolderMenu = app.menus[
            "scholium.folderRow.Cluster-01/Untitled Folder"
        ]
        XCTAssertTrue(createdFolderMenu.waitForExistence(timeout: 3))
        createdFolderMenu.menuItems["Rename Folder…"].click()
        let folderName = app.textFields["scholium.folderName"]
        XCTAssertTrue(folderName.waitForExistence(timeout: 5))
        typeCommittedText("Renamed Empty", into: folderName, in: app)
        app.buttons["Rename"].click()

        let renamedFolderURL = triptychDirectory.appendingPathComponent(
            "01-analyses/Cluster-01/Renamed Empty",
            isDirectory: true
        )
        XCTAssertTrue(waitUntil(timeout: 10) {
            FileManager.default.fileExists(atPath: renamedFolderURL.path)
                && !FileManager.default.fileExists(atPath: createdFolderURL.path)
        })
        let renamedFolderRow = app.descendants(matching: .any)[
            "scholium.folderRow.Cluster-01/Renamed Empty"
        ]
        XCTAssertTrue(renamedFolderRow.waitForExistence(timeout: 10))
        renamedFolderRow.rightClick()
        let renamedFolderMenu = app.menus[
            "scholium.folderRow.Cluster-01/Renamed Empty"
        ]
        XCTAssertTrue(renamedFolderMenu.waitForExistence(timeout: 3))
        renamedFolderMenu.menuItems["Move Folder and Notes to Trash…"].click()
        let folderTrashSheet = app.sheets.firstMatch
        XCTAssertTrue(folderTrashSheet.waitForExistence(timeout: 5))
        let confirmFolderTrash = folderTrashSheet.buttons[
            "Move Folder and Notes to Trash"
        ]
        XCTAssertTrue(confirmFolderTrash.waitForExistence(timeout: 5))
        confirmFolderTrash.click()
        let trashedFolderURL = triptychDirectory.appendingPathComponent(
            "01-analyses/Trash/Cluster-01/Renamed Empty",
            isDirectory: true
        )
        XCTAssertTrue(waitUntil(timeout: 10) {
            FileManager.default.fileExists(atPath: trashedFolderURL.path)
                && !FileManager.default.fileExists(atPath: renamedFolderURL.path)
        })

        if folderRow.value as? String == "Expanded" {
            folderRow.click()
            XCTAssertTrue(waitUntil(timeout: 5) {
                folderRow.value as? String == "Collapsed"
            })
        }
        XCTAssertEqual(folderRow.value as? String, "Collapsed")
        folderRow.rightClick()
        XCTAssertTrue(folderMenu.waitForExistence(timeout: 3))
        XCTAssertTrue(newNote.waitForExistence(timeout: 3))
        newNote.click()

        XCTAssertFalse(
            app.buttons["Create"].firstMatch.waitForExistence(timeout: 1),
            "Note creation must not route through the lifecycle sheet."
        )
        let createdURL = triptychDirectory.appendingPathComponent(
            "01-analyses/Cluster-01/Untitled.md"
        )
        XCTAssertTrue(waitUntil(timeout: 10) {
            FileManager.default.fileExists(atPath: createdURL.path)
        })
        XCTAssertEqual(try source(at: createdURL), "")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: triptychDirectory
                    .appendingPathComponent("01-analyses/Untitled.md")
                    .path
            )
        )

        let createdTitle = app.descendants(matching: .any)[
            "scholium.documentNoteName"
        ]
        XCTAssertTrue(waitUntil(timeout: 45) {
            createdTitle.value as? String == "Untitled"
        })
        let createdRow = app.descendants(matching: .any)[
            "scholium.noteRow.Cluster-01/Untitled.md"
        ]
        XCTAssertTrue(
            createdRow.waitForExistence(timeout: 10),
            "Creating inside a collapsed Folder must re-expand its ancestors."
        )
        XCTAssertTrue(waitUntil(timeout: 5) { createdRow.isSelected })
    }

    @MainActor
    func testRetiredNavigationMenuIsAbsent() {
        XCTAssertFalse(app.menuBars.menuBarItems["Navigate"].exists)
        XCTAssertFalse(app.menuItems["Back"].exists)
        XCTAssertFalse(app.menuItems["Forward"].exists)
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

        let vaultsPane = app.descendants(matching: .any)["Vaults"].firstMatch
        XCTAssertTrue(vaultsPane.waitForExistence(timeout: 10))
        vaultsPane.click()
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
    func testCleanAccountConfiguresAndRestoresACompleteTriptych() throws {
        app.terminate()

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
            .matching(identifier: "scholium.triptychSetup")
        let setup = setupSurfaces.firstMatch
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        XCTAssertEqual(
            setupSurfaces.count,
            1,
            "First launch must present one setup surface, not root setup plus a duplicate sheet."
        )
        XCTAssertTrue(app.staticTexts["Set Up Scholium"].exists)
        let setupFrame = app.windows.firstMatch.frame
        XCTAssertEqual(
            setupFrame.width,
            QABootstrapMetricContract.preferredWidth,
            accuracy: QAWorkspaceMetricContract.frameTolerance,
            "Bootstrap's 720pt contract is an initial size, not a minimum."
        )
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        XCTAssertFalse(app.splitGroups["scholium.workspaceSplitView"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.toggleSidebar"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.toggleInspector"].exists)

        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.click()
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

        let complete = app.buttons["Use This Triptych"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        XCTAssertFalse(complete.isEnabled)
        authorizePortableFolder(triptychDirectory)
        XCTAssertTrue(complete.isEnabled)
        complete.click()

        let analysesControl = app.buttons["Analyses"]
        let librarySurface = app.descendants(matching: .any)["scholium.librarySurface"]
        let loadingOverlay = app.descendants(matching: .any)["scholium.loadingOverlay"]
        XCTAssertTrue(waitUntil(timeout: 45) {
            analysesControl.exists && librarySurface.exists && !loadingOverlay.exists
        }, "Completing first-run setup must finish opening the Triptych and dismiss loading.")
        XCTAssertTrue(waitUntil(timeout: 10) {
            self.app.windows.count == 1
                && !self.app.descendants(matching: .any)["scholium.triptychSetup"].exists
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
        waitForDocumentSurface()
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
        let vaultsPane = app.descendants(matching: .any)["Vaults"].firstMatch
        XCTAssertTrue(vaultsPane.waitForExistence(timeout: 10))
        vaultsPane.click()
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
            .appendingPathComponent("ApplicationSupport/Workspace/workspace-registry-v2.json")
        XCTAssertTrue(waitUntil(timeout: 10) {
            (try? String(contentsOf: registryURL, encoding: .utf8))?
                .contains("QA Renamed Triptych") == true
        })
    }


    @MainActor
    func testResearchGuidanceUsesCurrentOwnerCategories() throws {
        let appMenu = app.menuBars.menuBarItems["Scholium QA"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()

        let categoryList = app.descendants(matching: .any)[
            "scholium.researchGuidance.categoryList"
        ]
        XCTAssertTrue(categoryList.waitForExistence(timeout: 10))
        for category in [
            "Methods",
            "Profiles & Practices",
            "Collaboration",
            "Sources & Integrations",
            "Recovery & Technical",
        ] {
            XCTAssertTrue(app.descendants(matching: .any)[
                "scholium.researchGuidance.category.\(category)"
            ].exists)
        }
        XCTAssertFalse(app.staticTexts["Researcher Skills"].exists)
        XCTAssertFalse(app.staticTexts["Permissions"].exists)

        app.descendants(matching: .any)[
            "scholium.researchGuidance.category.Methods"
        ].click()
        for actionID in [
            "discuss", "analyze", "synthesize", "write", "critique",
            "check-fidelity", "manuscript",
        ] {
            XCTAssertTrue(app.descendants(matching: .any)[
                "scholium.researchGuidance.method.\(actionID)"
            ].waitForExistence(timeout: 8))
        }

        app.descendants(matching: .any)[
            "scholium.researchGuidance.category.Profiles & Practices"
        ].click()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchGuidance.profilesPractices"
        ].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchGuidance.profile.analyze.enabled"
        ].exists)
        XCTAssertTrue(app.buttons["New Practice…"].exists)
        XCTAssertFalse(app.menuButtons["Add Skill"].exists)

        app.descendants(matching: .any)[
            "scholium.researchGuidance.category.Collaboration"
        ].click()
        let askEveryTime = app.radioButtons["Ask Me Every Time"]
        let askOnlyForWorks = app.radioButtons["Ask Me Only for Works"]
        let fullTriptychAccess = app.radioButtons["Full Triptych Access"]
        XCTAssertTrue(askEveryTime.waitForExistence(timeout: 8))
        XCTAssertTrue(askOnlyForWorks.exists)
        XCTAssertTrue(fullTriptychAccess.exists)
        askOnlyForWorks.click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            (askOnlyForWorks.value as? Int) == 1
                || (askOnlyForWorks.value as? String) == "1"
        })
        XCTAssertFalse(app.popUpButtons.matching(
            NSPredicate(format: "identifier CONTAINS %@", ".skill.")
        ).firstMatch.exists)

        app.descendants(matching: .any)[
            "scholium.researchGuidance.category.Sources & Integrations"
        ].click()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchGuidance.sources"
        ].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.agentCLI.section"
        ].waitForExistence(timeout: 8))

        app.descendants(matching: .any)[
            "scholium.researchGuidance.category.Recovery & Technical"
        ].click()
        let settledRetention = app.descendants(matching: .any)[
            "scholium.recovery.settledRetention"
        ]
        XCTAssertTrue(settledRetention.waitForExistence(timeout: 8))
        XCTAssertEqual(settledRetention.value as? String, "30 versions")
        settledRetention.click()
        let keepFifty = app.menuItems["50 versions"]
        XCTAssertTrue(keepFifty.waitForExistence(timeout: 5))
        keepFifty.click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            settledRetention.value as? String == "50 versions"
        })
        XCTAssertFalse(app.buttons["Reveal Skills Folder"].exists)
        XCTAssertFalse(app.buttons["Reveal Legacy Data"].exists)
    }

    @MainActor
    func testResearchGuidanceMarkdownCreationKeyboardAndDirtyClose() throws {
        openResearchGuidance()

        let settingsWindow = app.windows["Research Guidance"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        let newPractice = settingsWindow.buttons["New Practice…"]
        XCTAssertTrue(newPractice.waitForExistence(timeout: 5))
        newPractice.click()

        let creationSheet = settingsWindow.descendants(matching: .any)[
            "scholium.researchGuidance.markdownCreationSheet"
        ]
        XCTAssertTrue(creationSheet.waitForExistence(timeout: 5))
        let practiceTitle = creationSheet.textFields["Practice title"]
        let keyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
        XCTAssertTrue(practiceTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitUntil(timeout: 3) { keyboardFocus.evaluate(with: practiceTitle) },
            "A new Practice must begin at its title field."
        )

        try paste("QA Closure Practice", into: practiceTitle)
        let practiceSource = creationSheet.textViews[
            "Philosophical Practice Markdown"
        ]
        XCTAssertTrue(practiceSource.waitForExistence(timeout: 5))
        try paste(
            "# QA Closure Practice\n\nState the philosophical practice here.\n",
            into: practiceSource
        )
        practiceTitle.click()
        app.typeKey(.escape, modifierFlags: [])
        let keepEditing = settingsWindow.buttons["Keep Editing"]
        XCTAssertTrue(keepEditing.waitForExistence(timeout: 5))
        XCTAssertTrue(settingsWindow.buttons["Discard Draft and Close"].exists)
        keepEditing.click()
        XCTAssertTrue(creationSheet.exists)
        XCTAssertEqual(practiceTitle.value as? String, "QA Closure Practice")
        XCTAssertTrue(
            waitUntil(timeout: 3) { keyboardFocus.evaluate(with: practiceTitle) },
            "Keeping a dirty Practice draft must restore focus to the title field."
        )

        practiceTitle.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 10) { !creationSheet.exists },
            "Return in the title field must invoke the enabled default Create action."
        )
        XCTAssertTrue(settingsWindow.staticTexts[
            "QA Closure Practice"
        ].waitForExistence(timeout: 8))
    }


    @MainActor
    func testAcademicProfilePersistsAcrossSettingsReopen() throws {
        openResearchGuidance()

        let toggle = app.descendants(matching: .any)[
            "scholium.researchGuidance.profile.analyze.enabled"
        ]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.click()

        let profileURL = triptychDirectory
            .appendingPathComponent(".scholium", isDirectory: true)
            .appendingPathComponent("academic-action-profiles-v1.json")
        XCTAssertTrue(waitUntil(timeout: 10) {
            guard let data = try? Data(contentsOf: profileURL),
                  let root = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let profiles = root["profiles"] as? [[String: Any]],
                  let analyze = profiles.first(where: {
                      $0["actionID"] as? String == "analyze"
                  }) else { return false }
            return analyze["isEnabled"] as? Bool == false
        })

        let settingsWindow = app.windows["Research Guidance"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        settingsWindow.buttons[XCUIIdentifierCloseWindow].click()
        openResearchGuidance()
        let reopened = app.descendants(matching: .any)[
            "scholium.researchGuidance.profile.analyze.enabled"
        ]
        XCTAssertTrue(reopened.waitForExistence(timeout: 10))
        XCTAssertEqual(reopened.value as? String, "0")
    }


    @MainActor
    func testScholiumCLIInstallsFromSettings() throws {
        openResearchGuidance(openAdvanced: true)

        let section = app.descendants(matching: .any)["scholium.agentCLI.section"]
        let status = app.descendants(matching: .any)["scholium.agentCLI.status"]
        let install = app.descendants(matching: .any)["scholium.agentCLI.install"]
        XCTAssertTrue(section.waitForExistence(timeout: 10))
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Scholium CLI status")
        XCTAssertTrue(install.waitForExistence(timeout: 5))
        XCTAssertTrue(install.isEnabled)
        install.click()

        let installedTool = testDirectory.appendingPathComponent("cli-bin/scholium")
        let installedMethodResources = testDirectory.appendingPathComponent(
            "cli-bin/Scholium_ScholiumCore.bundle/Contents/Resources/Skills/README.md"
        )
        XCTAssertTrue(waitUntil(timeout: 15) {
            FileManager.default.isExecutableFile(atPath: installedTool.path)
                && FileManager.default.fileExists(atPath: installedMethodResources.path)
        })
        XCTAssertTrue(waitUntil(timeout: 10) {
            (status.value as? String) == "Installed"
                || (status.value as? String) == "Installed and discoverable"
        })
        XCTAssertFalse(install.exists)

        let copyPathSetup = app.descendants(matching: .any)[
            "scholium.agentCLI.pathSetup"
        ]
        XCTAssertTrue(copyPathSetup.waitForExistence(timeout: 5))
        try setPasteboardText("Scholium QA clipboard sentinel")
        copyPathSetup.click()
        let expectedSetup = "export PATH=\"$HOME/.local/bin:$PATH\""
        XCTAssertTrue(
            waitUntil(timeout: 5) { (try? self.pasteboardText()) == expectedSetup },
            "The shared pasteboard writer must copy the exact PATH setup command."
        )
        XCTAssertTrue(app.descendants(matching: .any)[
            "PATH setup copied"
        ].waitForExistence(timeout: 3))
    }


    @MainActor
    func testPointerActivationDoesNotRetainKeyboardOnlyFocus() {
        waitForDocumentSurface()
        selectResearchInspectorMode("actions")

        let keyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
        let actionsMode = app.buttons[
            "scholium.inspectorMode.actions"
        ].firstMatch
        XCTAssertTrue(actionsMode.waitForExistence(timeout: 5))
        actionsMode.click()
        XCTAssertFalse(
            keyboardFocus.evaluate(with: actionsMode),
            "Pointer activation must not leave a keyboard-only focus ring on the ModeIndex."
        )

        let discuss = app.descendants(matching: .any)[
            "scholium.researchAction.discuss"
        ].firstMatch
        XCTAssertTrue(discuss.waitForExistence(timeout: 5))
        discuss.click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.descendants(matching: .any)[
            "scholium.researchAction.sheet"
        ].waitForExistence(timeout: 8))
        let cancel = sheet.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !sheet.exists })

        for _ in 0..<12 where !keyboardFocus.evaluate(with: actionsMode) {
            app.typeKey(.tab, modifierFlags: [.shift])
        }
        XCTAssertTrue(
            keyboardFocus.evaluate(with: actionsMode),
            "The ModeIndex must retain its native keyboard focus path."
        )
        app.typeKey(.tab, modifierFlags: [])
        let actionButtons = ["discuss", "analyze", "check-fidelity"].map { id in
            app.descendants(matching: .any)[
                "scholium.researchAction.\(id)"
            ].firstMatch
        }
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                actionButtons.contains(where: {
                    keyboardFocus.evaluate(with: $0)
                })
            },
            "Tab from the ModeIndex must enter an available Action row."
        )
    }

    @MainActor
    func testResearchActionsRolePointerKeyboardFocusAccessibilityAndMinimumWidth() {
        waitForDocumentSurface()
        selectResearchInspectorMode("actions")

        func assertActions(_ expected: [(String, String)]) {
            let controls = expected.map { id, title in
                let control = app.descendants(matching: .any)[
                    "scholium.researchAction.\(id)"
                ].firstMatch
                XCTAssertTrue(control.waitForExistence(timeout: 8))
                XCTAssertTrue(control.label.localizedCaseInsensitiveContains(title))
                return control
            }
            for pair in zip(controls, controls.dropFirst()) {
                XCTAssertLessThan(pair.0.frame.minY, pair.1.frame.minY)
            }
        }

        assertActions([
            ("discuss", "Discuss"),
            ("analyze", "Analyze"),
            ("check-fidelity", "Check Fidelity"),
        ])
        XCTAssertFalse(app.staticTexts["Research Activity"].exists)
        XCTAssertFalse(app.buttons["Open Research Record"].exists)
        XCTAssertFalse(app.menuItems["Work with Agent"].exists)

        let analyze = app.descendants(matching: .any)["scholium.researchAction.analyze"]
        XCTAssertTrue(analyze.isEnabled && analyze.isHittable)
        analyze.click()
        var sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.descendants(matching: .any)[
            "scholium.researchAction.source.choose"
        ].waitForExistence(timeout: 8))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !sheet.exists })

        let discuss = app.descendants(matching: .any)["scholium.researchAction.discuss"]
        XCTAssertTrue(discuss.isEnabled && discuss.isHittable)
        discuss.click()
        sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.descendants(matching: .any)[
            "scholium.researchAction.sheet"
        ].waitForExistence(timeout: 8))
        XCTAssertTrue(sheet.descendants(matching: .any)[
            "scholium.researchAction.academicText.research-request"
        ].waitForExistence(timeout: 8))
        XCTAssertFalse(sheet.descendants(matching: .any)[
            "scholium.researchFunctionPanel"
        ].exists)
        let sheetScreenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        sheetScreenshot.name = "Research Action common sheet"
        sheetScreenshot.lifetime = .keepAlways
        add(sheetScreenshot)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !sheet.exists })

        let focusExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: discuss
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [focusExpectation], timeout: 3),
            .completed,
            "Keyboard dismissal must return focus to the initiating Discuss row."
        )

        app.typeKey("r", modifierFlags: [.command])
        sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.descendants(matching: .any)[
            "scholium.researchAction.sheet"
        ].waitForExistence(timeout: 8))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !sheet.exists })
        XCTAssertTrue(discuss.exists && discuss.isHittable)

        selectVault("scholium.vault.topic_knowledge", waitingFor: "scholium.noteRow.QA Topic.md")
        app.descendants(matching: .any)["scholium.noteRow.QA Topic.md"].click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            self.app.descendants(matching: .any)["scholium.documentNoteName"].value as? String
                == "QA Topic"
        })
        assertActions([
            ("discuss", "Discuss"),
            ("synthesize", "Synthesize"),
            ("check-fidelity", "Check Fidelity"),
        ])
        app.typeKey("r", modifierFlags: [.command, .shift])
        sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.staticTexts["Synthesize"].waitForExistence(timeout: 8))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !sheet.exists })

        selectVault("scholium.vault.output", waitingFor: "scholium.noteRow.QA Work.md")
        app.descendants(matching: .any)["scholium.noteRow.QA Work.md"].click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            self.app.descendants(matching: .any)["scholium.documentNoteName"].value as? String
                == "QA Work"
        })
        assertActions([
            ("discuss", "Discuss"),
            ("write", "Write"),
            ("critique", "Critique"),
            ("check-fidelity", "Check Fidelity"),
        ])
        app.menuBars.menuBarItems["Research"].click()
        for title in ["Discuss", "Write", "Critique", "Check Fidelity"] {
            XCTAssertTrue(app.menuItems[title].firstMatch.exists)
        }
        XCTAssertFalse(app.menuItems["Work with Agent"].exists)
        XCTAssertFalse(app.menuItems["Manuscript"].exists)
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("r", modifierFlags: [.command, .shift])
        sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.staticTexts["Write"].waitForExistence(timeout: 8))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !sheet.exists })

        app.descendants(matching: .any)["scholium.researchAction.check-fidelity"].click()
        sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.descendants(matching: .any)[
            "scholium.researchAction.sheet"
        ].waitForExistence(timeout: 8))
        let actionScroll = sheet.descendants(matching: .any)["scholium.researchAction.scroll"]
        let contentCheck = sheet.checkBoxes["Content"]
        scrollUntilHittable(contentCheck, in: actionScroll)
        contentCheck.click()
        let copyHandoff = sheet.descendants(matching: .any)[
            "scholium.researchAction.copyHandoff"
        ]
        XCTAssertTrue(copyHandoff.isEnabled && copyHandoff.isHittable)
        copyHandoff.click()
        let connection = sheet.descendants(matching: .any)["scholium.researchAction.connection"]
        XCTAssertTrue(connection.waitForExistence(timeout: 30))
        XCTAssertTrue(waitUntil(timeout: 5) {
            copyHandoff.exists && copyHandoff.isEnabled && copyHandoff.isHittable
        })
        XCTAssertFalse(sheet.descendants(matching: .any)[
            "scholium.researchAction.copyOnly"
        ].exists)
        XCTAssertFalse(sheet.descendants(matching: .any)[
            "scholium.researchAction.copyAndOpen"
        ].exists)
        XCTAssertFalse(sheet.descendants(matching: .any)[
            "scholium.researchAction.prepare"
        ].exists)
        let endAction = sheet.descendants(matching: .any)["scholium.researchAction.endAction"]
        XCTAssertTrue(endAction.isEnabled && endAction.isHittable)
        endAction.click()
        let confirmEndAction = app.buttons["End Action"].firstMatch
        XCTAssertTrue(confirmEndAction.waitForExistence(timeout: 5))
        confirmEndAction.click()
        XCTAssertTrue(waitUntil(timeout: 8) { !endAction.exists })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !sheet.exists })

        let workScreenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        workScreenshot.name = "Work Research Actions"
        workScreenshot.lifetime = .keepAlways
        add(workScreenshot)

        let window = app.windows.firstMatch
        resizeProofWindow(window, toWidth: 900)
        XCTAssertTrue(app.descendants(matching: .any)["scholium.researchAction.discuss"].exists)
        for id in ["discuss", "write", "critique", "check-fidelity"] {
            let action = app.descendants(matching: .any)["scholium.researchAction.\(id)"]
            XCTAssertGreaterThanOrEqual(action.frame.minX, window.frame.minX)
            XCTAssertLessThanOrEqual(action.frame.maxX, window.frame.maxX)
        }
    }

    @MainActor
    func testResearchActionsVoiceOverSpeechOrder() throws {
        guard ProcessInfo.processInfo.environment["SCHOLIUM_QA_ENABLE_VOICEOVER"] == "1" else {
            throw XCTSkip(
                "Real VoiceOver traversal is an explicit acceptance journey; set SCHOLIUM_QA_ENABLE_VOICEOVER=1 to run it."
            )
        }
        guard #available(macOS 27.0, *) else {
            throw XCTSkip("The VoiceOver UI-test service requires macOS 27 or newer.")
        }
        waitForDocumentSurface()
        selectResearchInspectorMode("actions")

        let voiceOver = XCUIDevice.shared.voiceOverService
        let wasEnabled = voiceOver.isEnabled
        defer {
            do {
                if wasEnabled && !voiceOver.isEnabled {
                    try voiceOver.enable()
                } else if !wasEnabled && voiceOver.isEnabled {
                    try voiceOver.disable()
                }
            } catch {
                XCTFail("Could not restore VoiceOver state: \(error.localizedDescription)")
            }
        }
        if !wasEnabled { try voiceOver.enable() }
        app.activate()

        func currentSpeech() throws -> String {
            var lastError: Error?
            for _ in 0..<3 {
                do { return try voiceOver.currentSpeech().utterance }
                catch {
                    lastError = error
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                }
            }
            throw lastError ?? NSError(
                domain: "ScholiumVoiceOverUITest",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "VoiceOver produced no speech."]
            )
        }

        func traverse(_ expected: [String], prefix: String) throws -> [String] {
            let discuss = app.descendants(matching: .any)["scholium.researchAction.discuss"]
            XCTAssertTrue(discuss.waitForExistence(timeout: 8))
            discuss.click()
            XCTAssertTrue(app.descendants(matching: .any)[
                "scholium.researchAction.sheet"
            ].waitForExistence(timeout: 8))
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntil(timeout: 3) {
                !self.app.descendants(matching: .any)["scholium.researchAction.sheet"].exists
            })
            app.typeKey(.F4, modifierFlags: [.control, .option, .shift])
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))

            var transcript = [try currentSpeech()]
            for _ in 0..<24 {
                if expected.allSatisfy({ expectedTitle in
                    transcript.contains(where: {
                        $0.localizedCaseInsensitiveContains(expectedTitle)
                    })
                }) { break }
                app.typeKey(.tab, modifierFlags: [])
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                transcript.append(try currentSpeech())
            }
            let indices = expected.compactMap { title in
                transcript.firstIndex(where: { $0.localizedCaseInsensitiveContains(title) })
            }
            XCTAssertEqual(indices.count, expected.count, "\(prefix) transcript: \(transcript)")
            XCTAssertEqual(indices, indices.sorted(), "\(prefix) Actions were announced out of order.")
            return transcript
        }

        var transcript = try traverse(
            ["Discuss", "Analyze", "Check Fidelity"],
            prefix: "Analysis"
        )
        selectVault("scholium.vault.topic_knowledge", waitingFor: "scholium.noteRow.QA Topic.md")
        app.descendants(matching: .any)["scholium.noteRow.QA Topic.md"].click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            self.app.descendants(matching: .any)["scholium.documentNoteName"].value as? String
                == "QA Topic"
        })
        transcript += try traverse(
            ["Discuss", "Synthesize", "Check Fidelity"],
            prefix: "Topic"
        )
        selectVault("scholium.vault.output", waitingFor: "scholium.noteRow.QA Work.md")
        app.descendants(matching: .any)["scholium.noteRow.QA Work.md"].click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            self.app.descendants(matching: .any)["scholium.documentNoteName"].value as? String
                == "QA Work"
        })
        transcript += try traverse(
            ["Discuss", "Write", "Critique", "Check Fidelity"],
            prefix: "Work"
        )

        let attachment = XCTAttachment(string: transcript.joined(separator: "\n"))
        attachment.name = "Research Actions VoiceOver transcript"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testResearchInspectorModePersistsAcrossNotesAndRelaunch() throws {
        waitForDocumentSurface()
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.researchStrip"].exists
        )

        let inspector = selectResearchInspectorMode("overview")
        XCTAssertEqual(
            inspector.frame.width,
            QAWorkspaceMetricContract.apparatusFirstRevealWidth,
            accuracy: QAWorkspaceMetricContract.frameTolerance,
            "The first explicit Inspector reveal should receive the provisional ideal width."
        )
        func attentionCount(_ value: String) -> XCUIElement {
            app.descendants(matching: .any)
                .matching(identifier: "scholium.researchOverview.attention")
                .matching(NSPredicate(format: "value == %@", "\(value) items"))
                .firstMatch
        }
        XCTAssertTrue(attentionCount("1").waitForExistence(timeout: 3))
        let overviewScreenshot = XCTAttachment(
            screenshot: app.windows.firstMatch.screenshot()
        )
        overviewScreenshot.name = "Inspector D-114 — Overview at first reveal"
        overviewScreenshot.lifetime = .keepAlways
        add(overviewScreenshot)
        selectResearchInspectorMode("connect")
        selectResearchInspectorMode("actions")

        let connectMode = app.buttons[
            "scholium.inspectorMode.connect"
        ].firstMatch
        let actionsMode = app.buttons[
            "scholium.inspectorMode.actions"
        ].firstMatch
        actionsMode.click()

        let keyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
        XCTAssertFalse(
            keyboardFocus.evaluate(with: actionsMode),
            "Pointer activation must not leave a keyboard-only focus ring on the ModeIndex."
        )
        func focusModeButton(_ button: XCUIElement) {
            for _ in 0..<12 where !keyboardFocus.evaluate(with: button) {
                app.typeKey(.tab, modifierFlags: [.shift])
            }
            XCTAssertTrue(
                keyboardFocus.evaluate(with: button),
                "The ModeIndex must be reachable from Inspector content by keyboard."
            )
        }

        focusModeButton(actionsMode)
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { connectMode.isSelected })
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { actionsMode.isSelected })

        focusModeButton(actionsMode)
        app.typeKey(.tab, modifierFlags: [])
        let actionButtons = ["discuss", "analyze", "check-fidelity"].map { id in
            app.descendants(matching: .any)[
                "scholium.researchAction.\(id)"
            ].firstMatch
        }
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                actionButtons.contains(where: {
                    keyboardFocus.evaluate(with: $0)
                })
            },
            "Tab from the ModeIndex must enter an available Action row."
        )

        let inspectorToggle = app.descendants(matching: .any)[
            "scholium.toggleInspector"
        ].firstMatch
        inspectorToggle.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })
        inspectorToggle.click()
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        XCTAssertEqual(
            inspector.frame.width,
            QAWorkspaceMetricContract.apparatusFirstRevealWidth,
            accuracy: QAWorkspaceMetricContract.frameTolerance,
            "Hiding and showing must not reassert or discard the current native width."
        )

        let secondRow = app.descendants(matching: .any)[
            "scholium.noteRow.QA Autosave B.md"
        ]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 8))
        secondRow.click()
        let documentTitle = app.descendants(matching: .any)[
            "scholium.documentNoteName"
        ]
        XCTAssertTrue(waitUntil(timeout: 8) {
            documentTitle.value as? String == "QA Autosave B"
        })
        XCTAssertTrue(actionsMode.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchAction.discuss"
        ].waitForExistence(timeout: 10))

        let sessionFile = homeDirectory
            .appendingPathComponent("ApplicationSupport/Window Sessions")
            .appendingPathComponent(sessionID.uuidString + ".json")
        XCTAssertTrue(waitUntil(timeout: 8) {
            guard let data = try? Data(contentsOf: sessionFile),
                  let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            return snapshot["inspectorMode"] as? String == "actions"
                && snapshot["inspectorVisible"] as? Bool == true
        })

        app.terminate()
        app = configuredApplication(sessionID: sessionID)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()
        XCTAssertTrue(app.buttons[
            "scholium.inspectorMode.actions"
        ].firstMatch.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchAction.discuss"
        ].waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.researchStrip"].exists
        )
    }


    @MainActor
    func testResearchActionsRemainUsableInLightAndDarkAppearances() {
        for appearance in QAAppearance.allCases {
            app.terminate()
            sessionID = UUID()
            app = configuredApplication(
                sessionID: sessionID,
                initialWorkspaceWidth: 1380,
                appearance: appearance
            )
            app.launch()
            XCTAssertTrue(
                app.windows.firstMatch.waitForExistence(timeout: 15),
                "The \(appearance.displayName) QA window did not appear."
            )
            waitForDocumentSurface()

            let window = app.windows.firstMatch
            selectResearchInspectorMode("actions")
            let actions = ["discuss", "analyze", "check-fidelity"].map { identifier in
                app.descendants(matching: .any)[
                    "scholium.researchAction.\(identifier)"
                ].firstMatch
            }
            for action in actions {
                XCTAssertTrue(action.exists)
                XCTAssertTrue(action.isHittable)
                XCTAssertGreaterThanOrEqual(action.frame.minX, window.frame.minX)
                XCTAssertLessThanOrEqual(action.frame.maxX, window.frame.maxX)
            }
            for pair in zip(actions, actions.dropFirst()) {
                XCTAssertLessThan(pair.0.frame.minY, pair.1.frame.minY)
            }

            let sheet = openDiscussFromActions()
            let panel = sheet.descendants(matching: .any)["scholium.researchAction.sheet"]
            XCTAssertTrue(panel.waitForExistence(timeout: 8))
            XCTAssertTrue(sheet.descendants(matching: .any)[
                "scholium.researchAction.boundary"
            ].exists)
            XCTAssertTrue(sheet.descendants(matching: .any)[
                "scholium.researchAction.noteSearch.materials"
            ].exists)
            XCTAssertTrue(sheet.descendants(matching: .any)[
                "scholium.researchAction.academicText.research-request"
            ].exists)
            XCTAssertTrue(sheet.buttons["Cancel"].exists)
            XCTAssertTrue(sheet.descendants(matching: .any)[
                "scholium.researchAction.copyHandoff"
            ].exists)
            XCTAssertFalse(sheet.descendants(matching: .any)[
                "scholium.researchAction.copyOnly"
            ].exists)
            XCTAssertFalse(sheet.descendants(matching: .any)[
                "scholium.researchAction.copyAndOpen"
            ].exists)
            XCTAssertFalse(sheet.descendants(matching: .any)[
                "scholium.researchAction.prepare"
            ].exists)

            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.name = "Actions Inspector and Discuss — \(appearance.displayName)"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntil(timeout: 3) { !panel.exists })
        }
    }

    @MainActor
    func testCritiqueActionUsesTriptychWorkingMethodWithoutAdHocPrompting() throws {
        waitForDocumentSurface()
        selectVault(
            "scholium.vault.output",
            waitingFor: "scholium.noteRow.QA Work.md"
        )

        let workRow = app.descendants(matching: .any)["scholium.noteRow.QA Work.md"]
        XCTAssertTrue(workRow.waitForExistence(timeout: 8))
        workRow.click()

        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
        XCTAssertTrue(waitUntil(timeout: 8) { metadata.value as? String == "QA Work" })
        selectResearchInspectorMode("actions")

        let critique = app.descendants(matching: .any)[
            "scholium.researchAction.critique"
        ]
        XCTAssertTrue(waitUntil(timeout: 5) {
            critique.exists && critique.isEnabled && critique.isHittable
        })
        critique.click()

        let panel = app.descendants(matching: .any)["scholium.researchAction.sheet"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["scholium.researchAction.boundary"].exists)
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchAction.noteSearch.materials"
        ].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchAction.academicText.research-request"
        ].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["scholium.researcherCommentsPanel"].exists)

        let copyHandoff = app.descendants(matching: .any)[
            "scholium.researchAction.copyHandoff"
        ]
        XCTAssertTrue(waitUntil(timeout: 5) {
            copyHandoff.isEnabled && copyHandoff.isHittable
        })
        copyHandoff.click()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchAction.connection"
        ].waitForExistence(timeout: 15))
        let copiedInstructions = try pasteboardText()
        XCTAssertTrue(copiedInstructions.contains("scholium-working-critique"))
        XCTAssertTrue(copiedInstructions.contains("QA Work.md"))
        XCTAssertTrue(panel.exists)
        app.buttons["Done"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !panel.exists })
    }


    @MainActor
    func testCritiqueFindingOpensExactWorkPassageInSource() throws {
        waitForDocumentSurface()
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
        finding.click()

        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
        XCTAssertTrue(waitUntil(timeout: 8) { metadata.value as? String == "QA Work" })
        let sourceEditor = app.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 8))
        XCTAssertTrue((sourceEditor.value as? String ?? "").contains("[[QA Topic]]"))
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertEqual(mode.value as? String, "Source")
    }

    @MainActor
    func testDocumentModesInspectorAndSearchAreKeyboardReachable() throws {
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.click()
        XCTAssertTrue(app.menuItems["Edit"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])

        let inspector = app.descendants(matching: .any)["scholium.toggleInspector"]
        XCTAssertTrue(inspector.exists)

        app.typeKey("f", modifierFlags: [.command, .shift])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
    }

    @MainActor
    func testEditorCommandsAreReachableFromNativeAndContextMenus() throws {
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.click()
        let livePreview = app.menuItems
            .matching(identifier: "text.page.badge.magnifyingglass")
            .firstMatch
        XCTAssertTrue(livePreview.waitForExistence(timeout: 3))
        livePreview.click()

        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        editor.click()

        let format = app.menuBars.menuBarItems["Format"]
        XCTAssertTrue(format.waitForExistence(timeout: 3))
        format.click()
        let bold = app.menuItems["Bold"].firstMatch
        XCTAssertTrue(bold.waitForExistence(timeout: 3))
        XCTAssertTrue(bold.isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        let insert = app.menuBars.menuBarItems["Insert"]
        XCTAssertTrue(insert.waitForExistence(timeout: 3))
        insert.click()
        XCTAssertTrue(app.menuItems["Footnote"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Table"].firstMatch.exists)
        let addComment = app.menuItems["Comment on Selection…"].firstMatch
        XCTAssertTrue(addComment.exists)
        XCTAssertFalse(addComment.isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        // Collapse any selection retained by the persistent editor session so
        // this context-menu assertion is deterministic. Comment belongs to
        // the transient selection toolbar, never the secondary-click menu.
        editor.typeKey(.rightArrow, modifierFlags: [])
        editor.rightClick()
        let editorContextMenu = app.menus["scholium.editor.contextMenu"]
        XCTAssertTrue(editorContextMenu.waitForExistence(timeout: 3))
        XCTAssertTrue(editorContextMenu.menuItems["Cut"].exists)
        XCTAssertTrue(editorContextMenu.menuItems["Copy"].exists)
        XCTAssertTrue(editorContextMenu.menuItems["Paste"].exists)
        XCTAssertTrue(editorContextMenu.menuItems["Select All"].exists)
        XCTAssertFalse(editorContextMenu.menuItems["Bold"].exists)
        XCTAssertFalse(editorContextMenu.menuItems["Emphasis"].exists)
        XCTAssertFalse(editorContextMenu.menuItems["Underline"].exists)
        XCTAssertFalse(editorContextMenu.menuItems["Link"].exists)
        XCTAssertFalse(editorContextMenu.menuItems["Font"].exists)
        XCTAssertFalse(editorContextMenu.menuItems["Typeface"].exists)
        XCTAssertFalse(editorContextMenu.menuItems["Preview"].exists)
        XCTAssertFalse(editorContextMenu.menuItems["Show Preview"].exists)
        XCTAssertFalse(editorContextMenu.menuItems["scholium.editor.agentComment"].exists)
        app.typeKey(.escape, modifierFlags: [])

        editor.typeKey(.upArrow, modifierFlags: [.command])
        editor.typeKey(.rightArrow, modifierFlags: [.shift])
        XCTAssertFalse(app.buttons["Comment"].exists)
        insert.click()
        XCTAssertTrue(addComment.exists)
        XCTAssertFalse(addComment.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        editor.typeKey("a", modifierFlags: [.command])
        editor.rightClick()
        XCTAssertTrue(editorContextMenu.menuItems["Cut"].isEnabled)
        XCTAssertTrue(editorContextMenu.menuItems["Copy"].isEnabled)
        XCTAssertFalse(editorContextMenu.menuItems[
            "scholium.editor.agentComment"
        ].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testReviewOwnsFootnoteNavigationAndEditKeepsItPassive() throws {
        let reference = app.buttons["Footnote 1"].firstMatch
        XCTAssertTrue(reference.waitForExistence(timeout: 8))
        reference.click()

        let returnToReference = app.buttons["Return to footnote reference 1"].firstMatch
        XCTAssertTrue(returnToReference.waitForExistence(timeout: 5))
        returnToReference.click()
        let referenceFocus = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: reference
        )
        XCTAssertEqual(XCTWaiter.wait(for: [referenceFocus], timeout: 5), .completed)

        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.click()
        let edit = app.menuItems["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["Markdown editor, Edit mode"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertFalse(app.buttons["Footnote 1"].exists)
        XCTAssertFalse(app.buttons["Return to footnote reference 1"].exists)

        mode.click()
        let source = app.menuItems["Source"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        source.click()
        XCTAssertTrue(app.descendants(matching: .any)["Markdown source editor"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Footnote 1"].exists)
        XCTAssertFalse(app.buttons["Return to footnote reference 1"].exists)
    }

    @MainActor
    func testLineCommentDiscussReopenAndFinish() throws {
        let noteURL = triptychDirectory
            .appendingPathComponent("01-analyses", isDirectory: true)
            .appendingPathComponent("QA Autosave A.md")
        let sourceBefore = try Data(contentsOf: noteURL)

        let review = app.descendants(matching: .any)["Rendered Markdown"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        let plainPassage = review.staticTexts.matching(NSPredicate(
            format: "value BEGINSWITH %@",
            "This is deterministic, disposable, nonprivate test material."
        )).firstMatch
        XCTAssertTrue(plainPassage.waitForExistence(timeout: 8))
        plainPassage.doubleClick()

        let addComment = app.buttons["Comment"].firstMatch
        XCTAssertTrue(addComment.waitForExistence(timeout: 3))
        addComment.click()

        let comment = app.textViews.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Comment for ")
        ).firstMatch
        XCTAssertTrue(comment.waitForExistence(timeout: 3))
        try paste("What follows from this passage?", into: comment)
        // XCU's WebKit text-view API mutates the accessibility value but does
        // not dispatch a DOM Return event. This visually hidden QA-only control
        // invokes the same submitComment closure; WKWebView integration tests
        // own the physical key semantics.
        let qaSubmitComment = app.buttons["Submit Comment for QA"]
        XCTAssertTrue(qaSubmitComment.waitForExistence(timeout: 3))
        qaSubmitComment.click()

        XCTAssertTrue(waitUntil(timeout: 5) { !comment.exists })
        XCTAssertFalse(app.descendants(matching: .any)["scholium.discussion"].exists)
        XCTAssertEqual(try Data(contentsOf: noteURL), sourceBefore)

        let activeDirectory = triptychDirectory
            .appendingPathComponent(".scholium", isDirectory: true)
            .appendingPathComponent("research-records/v1/active", isDirectory: true)
        XCTAssertTrue(waitUntil(timeout: 5) {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: activeDirectory,
                includingPropertiesForKeys: nil
            ) else { return false }
            return files.contains { file in
                guard file.pathExtension == "json",
                      let data = try? Data(contentsOf: file),
                      let text = String(data: data, encoding: .utf8) else { return false }
                return text.contains("What follows from this passage?")
            }
        })

        selectResearchInspectorMode("actions")
        let discuss = app.descendants(matching: .any)["scholium.researchAction.discuss"]
        XCTAssertTrue(discuss.waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntil(timeout: 8) { discuss.isEnabled })
        discuss.click()
        let actionSheet = app.descendants(matching: .any)[
            "scholium.researchAction.sheet"
        ]
        XCTAssertTrue(actionSheet.waitForExistence(timeout: 8))
        let request = app.descendants(matching: .any)[
            "scholium.researchAction.academicText.research-request"
        ]
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        XCTAssertTrue((request.value as? String)?.contains("existing Comments") == true)
        let copyHandoff = app.descendants(matching: .any)[
            "scholium.researchAction.copyHandoff"
        ]
        XCTAssertTrue(copyHandoff.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 8) { copyHandoff.isEnabled })
        copyHandoff.click()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchAction.connection"
        ].waitForExistence(timeout: 8))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !actionSheet.exists })

        discuss.click()
        var discussion = app.descendants(matching: .any)["scholium.discussion"]
        XCTAssertTrue(discussion.waitForExistence(timeout: 8))
        XCTAssertTrue(discussion.staticTexts["What follows from this passage?"].exists)
        XCTAssertTrue(discussion.staticTexts.matching(NSPredicate(
            format: "value BEGINSWITH %@",
            "The Discussion is waiting for an Agent reply."
        )).firstMatch.exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !discussion.exists })

        let activeFile = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: activeDirectory,
                includingPropertiesForKeys: nil
            ).first { $0.pathExtension == "json" }
        )
        let discussionID = activeFile.deletingPathExtension().lastPathComponent
        let cliOutput = try runScholiumCLI([
            "discuss", "reply", discussionID,
            "--agent", "Synthetic Agent",
            "--text", "A bounded synthetic reply.",
        ])
        XCTAssertTrue(cliOutput.contains("Recorded reply"))

        discuss.click()
        discussion = app.descendants(matching: .any)["scholium.discussion"]
        XCTAssertTrue(discussion.waitForExistence(timeout: 8))

        let finish = discussion.descendants(matching: .any)[
            "scholium.discussion.finish"
        ]
        XCTAssertTrue(finish.waitForExistence(timeout: 8))
        XCTAssertTrue(discussion.staticTexts["Synthetic Agent"].exists)
        XCTAssertTrue(discussion.staticTexts["A bounded synthetic reply."].exists)
        finish.click()
        XCTAssertTrue(waitUntil(timeout: 8) { !discussion.exists })
        XCTAssertTrue(discuss.exists)
        XCTAssertEqual(try Data(contentsOf: noteURL), sourceBefore)

        let recordRoot = triptychDirectory
            .appendingPathComponent(".scholium", isDirectory: true)
            .appendingPathComponent("research-records", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        let activeFiles = try FileManager.default.contentsOfDirectory(
            at: recordRoot.appendingPathComponent("active", isDirectory: true),
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        let finishedFiles = try FileManager.default.contentsOfDirectory(
            at: recordRoot.appendingPathComponent("records", isDirectory: true),
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        XCTAssertTrue(activeFiles.isEmpty)
        XCTAssertEqual(finishedFiles.count, 1)

        let recordID = try XCTUnwrap(
            UUID(uuidString: finishedFiles[0].deletingPathExtension().lastPathComponent)
        )
        let recordButton = app.buttons["scholium.showResearchRecords"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.click()
        let recordWindow = app.windows["Research Records"].firstMatch
        XCTAssertTrue(recordWindow.waitForExistence(timeout: 8))
        XCTAssertTrue(recordWindow.textFields[
            "scholium.researchRecord.search"
        ].waitForExistence(timeout: 8))
        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.list"
        ].exists)
        let row = recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.row.\(recordID.uuidString)"
        ]
        XCTAssertTrue(row.waitForExistence(timeout: 8))

        row.click()
        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.detail"
        ].waitForExistence(timeout: 5))
        XCTAssertTrue(recordWindow.staticTexts[
            "What follows from this passage?"
        ].waitForExistence(timeout: 5))
        XCTAssertTrue(recordWindow.staticTexts["Synthetic Agent"].exists)
        XCTAssertTrue(recordWindow.staticTexts["A bounded synthetic reply."].exists)
        XCTAssertTrue(recordWindow.staticTexts["Participating Notes"].exists)
        recordWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !recordWindow.exists })
    }

    @MainActor
    func testSearchThisNoteReportsMatchesNoResultsAndCloses() throws {
        let renderedDocument = app.descendants(matching: .any)["Rendered Markdown"]
        XCTAssertTrue(waitUntil(timeout: 20) { renderedDocument.exists })

        app.typeKey("f", modifierFlags: [.command])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        let field = app.descendants(matching: .any)["scholium.searchField"]
        let results = app.descendants(matching: .any).matching(
            identifier: "scholium.searchResult.QA Autosave A.md"
        )
        let result = results.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let searchMode = app.descendants(matching: .any)["scholium.searchMode"]
        let closeSearch = app.descendants(matching: .any)["scholium.closeSearchButton"]
        XCTAssertTrue(searchMode.waitForExistence(timeout: 5))
        XCTAssertTrue(closeSearch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.radioButtons["This Note"].exists)
        XCTAssertTrue(app.radioButtons["This Vault"].exists)
        XCTAssertTrue(app.radioButtons["Triptych"].exists)
        let collapsedControls = field.frame
            .union(searchMode.frame)
            .union(closeSearch.frame)
        XCTAssertLessThanOrEqual(collapsedControls.width, 644)
        XCTAssertLessThanOrEqual(collapsedControls.height, 80)

        app.radioButtons["This Note"].click()
        typeCommittedText("analysis", into: field, in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        let expandedContentHeight = result.frame.maxY - field.frame.minY
        XCTAssertGreaterThan(expandedContentHeight, collapsedControls.height)
        XCTAssertLessThanOrEqual(expandedContentHeight, 524)

        typeCommittedText("not in this rendered note", into: field, in: app)
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
        waitForDocumentSurface()

        app.typeKey("f", modifierFlags: [.command, .shift])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        let field = app.descendants(matching: .any)["scholium.searchField"]
        let result = app.descendants(matching: .any).matching(
            identifier: "scholium.searchResult.QA Autosave A.md"
        ).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let thisNote = app.radioButtons["This Note"]
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
        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))
        XCTAssertEqual(metadata.value as? String, "QA Autosave A")
        let sourceEditor = app.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(
            sourceEditor.waitForExistence(timeout: 10),
            "The selected Search result did not finish revealing its source range."
        )
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertEqual(mode.value as? String, "Source")
    }

    @MainActor
    func testSearchQueriesExplicitDirectRelationsWithoutParallelResults() throws {
        waitForDocumentSurface()

        app.typeKey("f", modifierFlags: [.command, .shift])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        let field = app.descendants(matching: .any)["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let triptych = app.radioButtons["Triptych"]
        XCTAssertTrue(triptych.waitForExistence(timeout: 5))
        triptych.click()
        typeCommittedText(
            "from-note:\"QA Direct Relation Concept 947\" relation:supports",
            into: field,
            in: app
        )

        let relatedAnalysis = app.descendants(matching: .any)[
            "scholium.searchResult.QA Autosave A.md"
        ]
        XCTAssertTrue(relatedAnalysis.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.searchResult.QA Direct Relation Topic.md"
        ].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@",
            "directly supported"
        )).firstMatch.exists)

        let resultScroll = app.outlines["scholium.searchResults"].firstMatch
        XCTAssertTrue(resultScroll.waitForExistence(timeout: 5))
        if !relatedAnalysis.isHittable {
            scrollUntilHittable(relatedAnalysis, in: resultScroll)
        }
        relatedAnalysis.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !search.exists })
        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))
        XCTAssertEqual(metadata.value as? String, "QA Autosave A")
    }

    @MainActor
    func testSearchExplainsTitleAliasHeadingAndBodyRanking() throws {
        waitForDocumentSurface()

        app.typeKey("f", modifierFlags: [.command, .shift])
        let field = app.descendants(matching: .any)["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let thisVault = app.radioButtons["This Vault"]
        XCTAssertTrue(thisVault.waitForExistence(timeout: 5))
        thisVault.click()
        typeCommittedText("deliberative autonomy", into: field, in: app)

        let title = app.descendants(matching: .any)["scholium.searchResult.Ranking Title.md"]
        let alias = app.descendants(matching: .any)["scholium.searchResult.Ranking Alias.md"]
        let heading = app.descendants(matching: .any)["scholium.searchResult.Ranking Heading.md"]
        let body = app.descendants(matching: .any)["scholium.searchResult.Ranking Body.md"]
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

    @MainActor
    func testResearchActionPanelFitsWideEditor() throws {
        waitForDocumentSurface()

        let wideWindow = app.windows.firstMatch
        guard wideWindow.frame.width >= 1_200 else {
            throw XCTSkip(
                "AppKit restored a narrower test-owned frame; rerun this journey from a clean QA preference domain."
            )
        }
        openResearchActionAndVerifyPanel(
            minimumWidth: 500,
            maximumWidth: 720,
            window: wideWindow
        )

        app.buttons["scholium.researchAction.dismiss"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !self.app.sheets.firstMatch.exists })
    }

    @MainActor
    func testResearchActionPanelFitsCompactEditor() throws {
        waitForDocumentSurface()

        let compactWindow = app.windows.firstMatch
        guard compactWindow.frame.width < 980 else {
            throw XCTSkip(
                "AppKit restored a wider test-owned frame; rerun this journey from a clean QA preference domain."
            )
        }
        openResearchActionAndVerifyPanel(
            minimumWidth: 500,
            maximumWidth: 720,
            window: compactWindow
        )
        app.buttons["scholium.researchAction.dismiss"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !self.app.sheets.firstMatch.exists })

        let compactWorks = app.buttons["scholium.vault.output"]
        if !compactWorks.exists {
            let sidebarToggle = app.buttons["Show Sidebar"].exists
                ? app.buttons["Show Sidebar"]
                : app.buttons["Hide Sidebar"]
            XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 3))
            sidebarToggle.click()
            XCTAssertTrue(app.descendants(matching: .any)[
                "scholium.librarySurface"
            ].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(compactWorks.waitForExistence(timeout: 5))
        compactWorks.click()
        let workRow = app.descendants(matching: .any)["scholium.noteRow.QA Work.md"]
        XCTAssertTrue(workRow.waitForExistence(timeout: 8))
        workRow.click()
        waitForDocumentSurface()
        openResearchActionAndVerifyPanel(
            minimumWidth: 500,
            maximumWidth: 720,
            window: compactWindow
        )
    }

    @MainActor

    func testResearchWorkflowInterfaceProofsUseOneAccessibleQARoute() {
        app.menuBars.menuBarItems["QA"].click()
        let openProofs = app.menuItems["Open Research Workflow Interface Proofs"]
        XCTAssertTrue(openProofs.waitForExistence(timeout: 3))
        openProofs.click()

        let proofWindow = app.windows["Research Workflow Interface Proofs"]
        XCTAssertTrue(
            proofWindow.waitForExistence(timeout: 8),
            "The Debug-only interface proof catalog did not open."
        )
        XCTAssertFalse(proofWindow.staticTexts["Research Activity"].exists)
        XCTAssertFalse(proofWindow.buttons["Open Research Record"].exists)

        proofWindow.staticTexts["Skill-run Sheet"].click()
        XCTAssertTrue(proofWindow.buttons["Begin Analyze"].waitForExistence(timeout: 3))
        XCTAssertTrue(proofWindow.buttons["Nagel, What Is It Like to Be a Bat?.pdf"].exists)

        proofWindow.staticTexts["Skill Installer"].click()
        XCTAssertTrue(proofWindow.buttons["Install Disabled"].waitForExistence(timeout: 3))

        proofWindow.staticTexts["Skill Settings"].click()
        XCTAssertTrue(
            proofWindow.staticTexts["WORKING METHOD SKILLS"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(proofWindow.staticTexts["SYSTEM SKILLS"].exists)

        proofWindow.staticTexts["Bounded Write Set"].click()
        XCTAssertTrue(
            proofWindow.buttons["Allow Selected Notes"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(proofWindow.buttons["Continue Without Changes"].exists)
        XCTAssertTrue(proofWindow.buttons["Cancel Request"].exists)

        proofWindow.staticTexts["Research Record"].click()
        XCTAssertTrue(proofWindow.textFields["Search records"].waitForExistence(timeout: 3))
        XCTAssertTrue(proofWindow.staticTexts["Date"].exists)
        XCTAssertTrue(proofWindow.staticTexts["Skill"].exists)
        XCTAssertTrue(proofWindow.staticTexts["Action"].exists)
        XCTAssertTrue(proofWindow.staticTexts["Participant"].exists)
        XCTAssertFalse(proofWindow.buttons["Back to Records"].exists)
    }

    @MainActor
    func testResearchWriteSetExtensionSheetUsesNativeBoundedDecisionUI() {
        let window = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        guard let windowID = UUID(uuidString: String(window.identifier.suffix(36))) else {
            XCTFail("The workspace window must expose its exact route identity.")
            return
        }

        XCTAssertEqual(
            notify_post(
                "com.scholium.qa.present-write-set-extension.\(windowID.uuidString)"
            ),
            UInt32(NOTIFY_STATUS_OK)
        )

        let sheet = app.descendants(matching: .any)[
            "scholium.researchWriteSetExtension.sheet"
        ]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Allow Selected Notes"].exists)
        XCTAssertTrue(app.buttons["Continue Without Changes"].exists)
        XCTAssertTrue(app.buttons["Cancel Request"].exists)
        XCTAssertTrue(app.staticTexts["ACADEMIC REASON"].exists)
        XCTAssertTrue(app.staticTexts["REQUESTED NOTES"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !sheet.exists })
        XCTAssertTrue(window.exists)
    }

}
