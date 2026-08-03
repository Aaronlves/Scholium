import AppKit
import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    private struct PresentationContract: Decodable {
        struct Probe: Decodable {
            let id: String
            let semanticRole: String
            let sourceToken: String
            let sourceOccurrence: Int?
            let visibleToken: String?
            let visibleEndToken: String?
            let level: String
            let readSelector: String
            let editSelector: String
            let expectation: String
            let adapterStyleKeys: [String]?
            let compareVisibleStart: Bool?
        }

        let comparisonProbes: [Probe]
    }

    private struct GeometrySnapshot: Codable {
        struct Probe: Codable {
            let id: String
            let found: Bool
            let text: String
            let top: Double
            let bottom: Double
            let left: Double
            let right: Double
            let width: Double
            let height: Double
            let lineCount: Int
            let lineTops: [Double]
            let lineWidths: [Double]
            let visibleStart: Double?
            let widgetBufferCount: Int
            let widgetBufferHeight: Double
            let widgetBufferFontSize: String
            let styles: [String: String]
        }

        let surface: String
        let viewportWidth: Double
        let contentHeight: Double
        let probes: [Probe]
    }

    private struct GeometryComparisonReport: Encodable {
        struct Difference: Encodable {
            let id: String
            let sourceUTF16LowerBound: Int
            let sourceUTF16UpperBound: Int
            let semanticRole: String
            let level: String
            let expectation: String
            let read: GeometrySnapshot.Probe
            let edit: GeometrySnapshot.Probe
            let styleDifferences: [String: [String]]
            let adapterStyleDifferences: [String: [String]]
            let topDelta: Double
            let heightDelta: Double
            let lineCountDelta: Int
            let visibleStartDelta: Double?
            let precedingReadBlockID: String?
            let precedingEditBlockID: String?
            let precedingBlockOrderMatches: Bool?
            let precedingBlockGapDelta: Double?
        }

        let fixtureFingerprint: String
        let viewportWidth: Double
        let readContentHeight: Double
        let editContentHeight: Double
        let contentHeightDelta: Double
        let mustMatchDifferenceCount: Int
        let readBlockOrder: [String]
        let editBlockOrder: [String]
        let probes: [Difference]
    }

    @Test("The fixed catalog yields a complete Review and inactive-Edit geometry baseline")
    func fixedCatalogProducesCompletePresentationBaseline() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureDirectory = repository.appendingPathComponent("Tests/Fixtures/Editor")
        let sourceData = try Data(
            contentsOf: fixtureDirectory.appendingPathComponent("three-mode-contract.md")
        )
        let source = String(decoding: sourceData, as: UTF8.self)
        let contract = try JSONDecoder().decode(
            PresentationContract.self,
            from: Data(
                contentsOf: fixtureDirectory.appendingPathComponent("three-mode-contract.json")
            )
        )
        #expect(contract.comparisonProbes.count >= 20)
        #expect(Set(contract.comparisonProbes.map(\.id)).count == contract.comparisonProbes.count)

        let document = NoteDocument(relativePath: "ThreeModeContract.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)

        let probeArguments = try contract.comparisonProbes.map { probe -> [String: Any] in
            guard let anchorRange = sourceRange(
                of: probe.sourceToken,
                occurrence: probe.sourceOccurrence ?? 1,
                in: source
            ) else {
                throw MarkdownEditorSession.SessionError.invalidResult
            }
            let sourceRange = try semanticSourceRange(
                role: probe.semanticRole,
                containing: anchorRange,
                in: source,
                semantic: semantic
            )
            var argument: [String: Any] = [
                "id": probe.id,
                "semanticRole": probe.semanticRole,
                "level": probe.level,
                "expectation": probe.expectation,
                "readSelector": probe.readSelector,
                "editSelector": probe.editSelector,
                "sourceFrom": sourceRange.lowerBound,
                "sourceTo": sourceRange.upperBound,
            ]
            if let visibleToken = probe.visibleToken {
                argument["visibleToken"] = visibleToken
            }
            if let visibleEndToken = probe.visibleEndToken {
                argument["visibleEndToken"] = visibleEndToken
            }
            if probe.compareVisibleStart == true {
                argument["compareVisibleStart"] = true
            }
            return argument
        }

        let scenario = try #require(Self.testingPresentationScenarios.first {
            $0.name == "workspace-900"
        })
        let readHarness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { readHarness.close() }
        try await readHarness.waitUntilReady()
        _ = try await readHarness.presentationSnapshots(for: [scenario])
        readHarness.resize(width: scenario.width, height: 4_800)
        let readSnapshot = try await waitForGeometrySnapshot(
            surface: "Review",
            rootSelector: ".scholium-document",
            selectorKey: "readSelector",
            probes: probeArguments,
            evaluate: readHarness.callPageJavaScript
        )
        let readTaskControls = try #require(try await readHarness.callPageJavaScript(
            """
            return {
              count: document.querySelectorAll('.scholium-task-checkbox').length,
              checked: document.querySelectorAll('.scholium-task-checkbox:checked').length,
              disabled: document.querySelectorAll('.scholium-task-checkbox:disabled').length,
              labels: Array.from(document.querySelectorAll('.scholium-task-checkbox'))
                .map(control => control.getAttribute('aria-label'))
            };
            """
        ) as? [String: Any])
        await readHarness.closeAndDrain()

        let editHarness = EditorHarness(
            documentID: "ThreeModeContract.md",
            source: source,
            initialPresentationCSS: scenario.presentationCSS
        )
        defer { editHarness.close() }
        try await editHarness.waitUntilReady()
        let anchorRange = try #require(source.range(of: "INACTIVE_EDIT_ANCHOR"))
        let anchor = anchorRange.lowerBound.utf16Offset(in: source)
        editHarness.session.revealSourceRange(fromUTF16: anchor, toUTF16: anchor)
        try await editHarness.waitUntilSelection(head: anchor)
        _ = try await editHarness.presentationSnapshots(for: [scenario])
        editHarness.resize(width: scenario.width, height: 4_800)
        let editSnapshot = try await waitForGeometrySnapshot(
            surface: "Inactive Edit",
            rootSelector: ".cm-content",
            selectorKey: "editSelector",
            probes: probeArguments,
            evaluate: editHarness.callPageJavaScript
        )
        let editTaskControls = try #require(try await editHarness.callPageJavaScript(
            """
            return {
              count: document.querySelectorAll('.cm-live-task-checkbox').length,
              checked: document.querySelectorAll('.cm-live-task-checkbox:checked').length
            };
            """
        ) as? [String: Any])
        #expect(try await editHarness.session.currentText(for: editHarness.documentID) == source)
        await editHarness.closeAndDrain()

        let report = try comparisonReport(
            source: source,
            contract: contract,
            probeArguments: probeArguments,
            read: readSnapshot,
            edit: editSnapshot
        )
        let outputDirectory = repository.appendingPathComponent(
            ".build/editor-presentation-comparison",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(
            to: outputDirectory.appendingPathComponent("baseline.json"),
            options: .atomic
        )

        #expect(readSnapshot.probes.allSatisfy { $0.found })
        #expect(editSnapshot.probes.allSatisfy { $0.found })
        #expect(abs(readSnapshot.viewportWidth - editSnapshot.viewportWidth) <= 1)
        #expect(report.probes.count == contract.comparisonProbes.count)
        #expect(report.readBlockOrder == report.editBlockOrder)
        #expect(report.probes.allSatisfy {
            $0.sourceUTF16LowerBound >= 0
                && $0.sourceUTF16UpperBound > $0.sourceUTF16LowerBound
                && $0.read.height > 0
                && $0.edit.height > 0
        })
        #expect(readTaskControls["count"] as? Int == 2)
        #expect(readTaskControls["checked"] as? Int == 1)
        #expect(readTaskControls["disabled"] as? Int == 2)
        #expect(
            readTaskControls["labels"] as? [String]
                == ["Incomplete task", "Completed task"]
        )
        #expect(editTaskControls["count"] as? Int == 2)
        #expect(editTaskControls["checked"] as? Int == 1)
        for id in [
            "unordered-list-item",
            "nested-list-item",
            "task-list-item",
            "checked-task-list-item",
            "ordered-list-item",
        ] {
            let difference = try #require(report.probes.first { $0.id == id })
            // Two independent WKWebViews may quantize the same CSS `em`
            // track to adjacent subpixels. A whole CSS pixel is the adapter
            // tolerance; the pre-fix semantic drift was 5–29 pixels.
            #expect(abs(try #require(difference.visibleStartDelta)) <= 1)
        }
        let mermaid = try #require(report.probes.first { $0.id == "mermaid-diagram" })
        #expect(mermaid.styleDifferences.isEmpty)
        #expect(abs(mermaid.heightDelta) <= 0.5)
        #expect(mermaid.lineCountDelta == 0)
        #expect(mermaid.precedingBlockOrderMatches == true)
        #expect(abs(mermaid.precedingBlockGapDelta ?? 0) <= 0.5)
    }

    private func waitForGeometrySnapshot(
        surface: String,
        rootSelector: String,
        selectorKey: String,
        probes: [[String: Any]],
        evaluate: (String, [String: Any]) async throws -> Any?
    ) async throws -> GeometrySnapshot {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(8))
        var latest: GeometrySnapshot?
        while clock.now < deadline {
            let result = try await evaluate(Self.geometrySnapshotJavaScript, [
                "surface": surface,
                "rootSelector": rootSelector,
                "selectorKey": selectorKey,
                "probes": probes,
            ])
            if JSONSerialization.isValidJSONObject(result as Any) {
                let data = try JSONSerialization.data(withJSONObject: result as Any)
                latest = try JSONDecoder().decode(GeometrySnapshot.self, from: data)
                if latest?.probes.allSatisfy(\.found) == true {
                    try await Task.sleep(for: .milliseconds(100))
                    return try await stableGeometrySnapshot(
                        surface: surface,
                        rootSelector: rootSelector,
                        selectorKey: selectorKey,
                        probes: probes,
                        evaluate: evaluate
                    )
                }
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        let missing = latest?.probes.filter { !$0.found }
            .map { "\($0.id) [\($0.text)]" }
            .joined(separator: ", ")
            ?? "all probes"
        Issue.record("\(surface) did not materialize the fixed catalog probes: \(missing).")
        throw MarkdownEditorSession.SessionError.invalidResult
    }

    private func stableGeometrySnapshot(
        surface: String,
        rootSelector: String,
        selectorKey: String,
        probes: [[String: Any]],
        evaluate: (String, [String: Any]) async throws -> Any?
    ) async throws -> GeometrySnapshot {
        let result = try await evaluate(Self.geometrySnapshotJavaScript, [
            "surface": surface,
            "rootSelector": rootSelector,
            "selectorKey": selectorKey,
            "probes": probes,
        ])
        guard JSONSerialization.isValidJSONObject(result as Any) else {
            throw MarkdownEditorSession.SessionError.invalidResult
        }
        return try JSONDecoder().decode(
            GeometrySnapshot.self,
            from: JSONSerialization.data(withJSONObject: result as Any)
        )
    }

    private func comparisonReport(
        source: String,
        contract: PresentationContract,
        probeArguments: [[String: Any]],
        read: GeometrySnapshot,
        edit: GeometrySnapshot
    ) throws -> GeometryComparisonReport {
        let readByID = Dictionary(uniqueKeysWithValues: read.probes.map { ($0.id, $0) })
        let editByID = Dictionary(uniqueKeysWithValues: edit.probes.map { ($0.id, $0) })
        let argumentsByID = Dictionary(uniqueKeysWithValues: probeArguments.compactMap { value in
            (value["id"] as? String).map { ($0, value) }
        })
        var differences: [GeometryComparisonReport.Difference] = []
        var mustMatchDifferenceCount = 0

        let blockIDs = Set(contract.comparisonProbes.lazy
            .filter { $0.level == "block" && $0.expectation == "mustMatchReview" }
            .map(\.id))
        let readBlockOrder = read.probes
            .filter { blockIDs.contains($0.id) }
            .sorted { $0.top < $1.top }
            .map(\.id)
        let editBlockOrder = edit.probes
            .filter { blockIDs.contains($0.id) }
            .sorted { $0.top < $1.top }
            .map(\.id)
        let readPredecessors = Dictionary(uniqueKeysWithValues: zip(
            readBlockOrder.dropFirst(),
            readBlockOrder.dropLast()
        ))
        let editPredecessors = Dictionary(uniqueKeysWithValues: zip(
            editBlockOrder.dropFirst(),
            editBlockOrder.dropLast()
        ))

        let ordered = contract.comparisonProbes.sorted { left, right in
            let leftFrom = argumentsByID[left.id]?["sourceFrom"] as? Int ?? 0
            let rightFrom = argumentsByID[right.id]?["sourceFrom"] as? Int ?? 0
            return leftFrom < rightFrom
        }
        for probe in ordered {
            let readProbe = try #require(readByID[probe.id])
            let editProbe = try #require(editByID[probe.id])
            let argument = try #require(argumentsByID[probe.id])
            let styleKeys = Set(readProbe.styles.keys).union(editProbe.styles.keys)
            let observedStyleDifferences = Dictionary(uniqueKeysWithValues: styleKeys.compactMap { key in
                let readValue = readProbe.styles[key] ?? ""
                let editValue = editProbe.styles[key] ?? ""
                return readValue == editValue ? nil : (key, [readValue, editValue])
            })
            // CodeMirror must preserve exact whitespace in its contenteditable
            // source DOM. `break-spaces` is therefore an adapter mechanism, not
            // a visual mismatch when the measured line bands are identical.
            let adapterStyleKeys = Set(["white-space"] + (probe.adapterStyleKeys ?? []))
            let styleDifferences = observedStyleDifferences.filter {
                !adapterStyleKeys.contains($0.key)
            }
            let adapterStyleDifferences = observedStyleDifferences.filter {
                adapterStyleKeys.contains($0.key)
            }
            let precedingReadBlockID = probe.level == "block"
                ? readPredecessors[probe.id]
                : nil
            let precedingEditBlockID = probe.level == "block"
                ? editPredecessors[probe.id]
                : nil
            let precedingBlockOrderMatches = probe.level == "block"
                ? precedingReadBlockID == precedingEditBlockID
                : nil
            let precedingGapDelta: Double?
            if precedingBlockOrderMatches == true,
               let precedingID = precedingReadBlockID,
               let precedingReadProbe = readByID[precedingID],
               let precedingEditProbe = editByID[precedingID] {
                precedingGapDelta = (editProbe.top - precedingEditProbe.bottom)
                    - (readProbe.top - precedingReadProbe.bottom)
            } else {
                precedingGapDelta = nil
            }
            let topDelta = editProbe.top - readProbe.top
            let heightDelta = editProbe.height - readProbe.height
            let lineCountDelta = editProbe.lineCount - readProbe.lineCount
            let visibleStartDelta: Double?
            if let readStart = readProbe.visibleStart,
               let editStart = editProbe.visibleStart {
                visibleStartDelta = editStart - readStart
            } else {
                visibleStartDelta = nil
            }
            if probe.expectation == "mustMatchReview",
               !styleDifferences.isEmpty
                || abs(topDelta) > 0.5
                || abs(heightDelta) > 0.5
                || lineCountDelta != 0
                || probe.compareVisibleStart == true
                    && abs(visibleStartDelta ?? .infinity) > 1
                || precedingBlockOrderMatches == false
                || abs(precedingGapDelta ?? 0) > 0.5 {
                mustMatchDifferenceCount += 1
            }
            differences.append(.init(
                id: probe.id,
                sourceUTF16LowerBound: try #require(argument["sourceFrom"] as? Int),
                sourceUTF16UpperBound: try #require(argument["sourceTo"] as? Int),
                semanticRole: probe.semanticRole,
                level: probe.level,
                expectation: probe.expectation,
                read: readProbe,
                edit: editProbe,
                styleDifferences: styleDifferences,
                adapterStyleDifferences: adapterStyleDifferences,
                topDelta: topDelta,
                heightDelta: heightDelta,
                lineCountDelta: lineCountDelta,
                visibleStartDelta: visibleStartDelta,
                precedingReadBlockID: precedingReadBlockID,
                precedingEditBlockID: precedingEditBlockID,
                precedingBlockOrderMatches: precedingBlockOrderMatches,
                precedingBlockGapDelta: precedingGapDelta
            ))
        }

        return GeometryComparisonReport(
            fixtureFingerprint: DocumentFingerprint(content: source).sha256,
            viewportWidth: read.viewportWidth,
            readContentHeight: read.contentHeight,
            editContentHeight: edit.contentHeight,
            contentHeightDelta: edit.contentHeight - read.contentHeight,
            mustMatchDifferenceCount: mustMatchDifferenceCount,
            readBlockOrder: readBlockOrder,
            editBlockOrder: editBlockOrder,
            probes: differences
        )
    }

    private func sourceRange(
        of token: String,
        occurrence: Int,
        in source: String
    ) -> Range<String.Index>? {
        guard occurrence > 0 else { return nil }
        var lowerBound = source.startIndex
        for index in 1 ... occurrence {
            guard let range = source.range(of: token, range: lowerBound..<source.endIndex) else {
                return nil
            }
            if index == occurrence { return range }
            lowerBound = range.upperBound
        }
        return nil
    }

    private func semanticSourceRange(
        role: String,
        containing anchor: Range<String.Index>,
        in source: String,
        semantic: MarkdownSemanticDocument
    ) throws -> Range<Int> {
        let anchorRange = anchor.lowerBound.utf16Offset(in: source)
            ..< anchor.upperBound.utf16Offset(in: source)
        let ranges: [Range<Int>]
        switch role {
        case "heading":
            ranges = semantic.headings.map(\.span.utf16Range)
        case "paragraph":
            ranges = semantic.blocks.filter { $0.kind == .paragraph }.map(\.span.utf16Range)
        case "strong":
            ranges = semantic.inlines.filter { $0.kind == .strong }.map(\.span.utf16Range)
        case "emphasis":
            ranges = semantic.inlines.filter { $0.kind == .emphasis }.map(\.span.utf16Range)
        case "strikethrough":
            ranges = semantic.inlines.filter { $0.kind == .strikethrough }.map(\.span.utf16Range)
        case "highlight":
            ranges = semantic.inlines.filter { $0.kind == .highlight }.map(\.span.utf16Range)
        case "inlineCode":
            ranges = semantic.inlines.filter { $0.kind == .code }.map(\.span.utf16Range)
        case "link":
            ranges = semantic.links.filter { $0.syntax == .markdown }.map(\.span.utf16Range)
        case "wikilink":
            ranges = semantic.links.filter { $0.syntax == .wikilink || $0.syntax == .vectorWikilink }
                .map(\.span.utf16Range)
        case "listItem":
            ranges = semantic.blocks.filter { $0.kind == .listItem }.map(\.span.utf16Range)
        case "blockQuote":
            ranges = semantic.blocks.filter { $0.kind == .blockQuote }.map(\.span.utf16Range)
        case "codeBlock":
            ranges = semantic.blocks.filter { $0.kind == .code }.map(\.span.utf16Range)
        case "thematicBreak":
            ranges = semantic.blocks.filter { $0.kind == .thematicBreak }.map(\.span.utf16Range)
        case "table":
            ranges = semantic.blocks.filter { $0.kind == .table }.map(\.span.utf16Range)
        case "callout":
            ranges = semantic.callouts.map(\.span.utf16Range)
        case "math":
            ranges = semantic.mathExpressions.map(\.span.utf16Range)
        case "footnoteDefinition":
            ranges = semantic.footnoteDefinitions.map(\.span.utf16Range)
        case "html":
            ranges = semantic.blocks.filter { $0.kind == .html }.map(\.span.utf16Range)
        default:
            throw MarkdownEditorSession.SessionError.invalidResult
        }
        guard let range = ranges
            .filter({ $0.lowerBound <= anchorRange.lowerBound && $0.upperBound >= anchorRange.upperBound })
            .min(by: { $0.count < $1.count }) else {
            Issue.record("No \(role) semantic range contains source anchor \(anchorRange).")
            throw MarkdownEditorSession.SessionError.invalidResult
        }
        return range
    }

    private static let geometrySnapshotJavaScript = """
    const root = document.querySelector(rootSelector);
    if (!root) return null;
    const rootRect = root.getBoundingClientRect();
    const rounded = value => Math.round(value * 1000) / 1000;
    const styleKeys = [
      'font-family', 'font-size', 'font-weight', 'font-style', 'line-height',
      'letter-spacing', 'text-align', 'color', 'background-color', 'direction',
      'white-space', 'overflow-wrap', 'margin-block-start', 'margin-block-end',
      'margin-inline-start', 'margin-inline-end',
      'padding-block-start', 'padding-block-end', 'padding-inline-start',
      'padding-inline-end', 'border-inline-start-width', 'border-inline-start-color',
      'border-radius', 'box-sizing', 'display', 'text-decoration-line',
      'text-decoration-color', 'text-underline-offset'
    ];
    const measure = probe => {
      const selector = probe[selectorKey];
      const candidates = Array.from(document.querySelectorAll(selector));
      const contains = (element, token) => !token || (element.textContent || '').includes(token);
      const startIndex = candidates.findIndex(element => contains(element, probe.visibleToken));
      if (startIndex < 0) {
        const globalMatches = probe.visibleToken
          ? Array.from(document.querySelectorAll('*')).filter(element =>
              (element.textContent || '').includes(probe.visibleToken)
            ).slice(-5)
          : [];
        return {
          id: probe.id,
          found: false,
          text: [
            ...candidates.slice(0, 5).map(element => element.textContent || ''),
            ...globalMatches.map(element =>
              `${element.tagName}.${element.className || ''}: ${(element.textContent || '').slice(0, 120)}`
            )
          ].join(' | '),
          top: 0, bottom: 0, left: 0,
          right: 0, width: 0, height: 0, lineCount: 0, lineTops: [],
          lineWidths: [], widgetBufferCount: 0, widgetBufferHeight: 0,
          widgetBufferFontSize: '', styles: {}
        };
      }
      let endIndex = startIndex;
      if (probe.visibleEndToken) {
        const relativeEnd = candidates.slice(startIndex).findIndex(element =>
          contains(element, probe.visibleEndToken)
        );
        if (relativeEnd >= 0) endIndex = startIndex + relativeEnd;
      }
      const selected = candidates.slice(startIndex, endIndex + 1);
      const bounds = selected.map(element => element.getBoundingClientRect());
      const left = Math.min(...bounds.map(rect => rect.left));
      const right = Math.max(...bounds.map(rect => rect.right));
      const top = Math.min(...bounds.map(rect => rect.top));
      const bottom = Math.max(...bounds.map(rect => rect.bottom));
      const textRects = [];
      for (const element of selected) {
        const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
          if (!node.textContent || !node.textContent.trim()) continue;
          const parent = node.parentElement;
          if (!parent || getComputedStyle(parent).display === 'none') continue;
          const range = document.createRange();
          range.selectNodeContents(node);
          for (const rect of Array.from(range.getClientRects())) {
            if (rect.width <= 0 || rect.height <= 0) continue;
            textRects.push({
              top: rect.top,
              bottom: rect.bottom,
              left: rect.left,
              right: rect.right
            });
          }
        }
      }
      textRects.sort((a, b) => a.top - b.top || a.left - b.left);
      const orderedLines = [];
      for (const rect of textRects) {
        const existing = orderedLines.find(line =>
          rect.bottom > line.top + 0.5 && rect.top < line.bottom - 0.5
        );
        if (existing) {
          existing.top = Math.min(existing.top, rect.top);
          existing.bottom = Math.max(existing.bottom, rect.bottom);
          existing.left = Math.min(existing.left, rect.left);
          existing.right = Math.max(existing.right, rect.right);
        } else {
          orderedLines.push({...rect});
        }
      }
      orderedLines.sort((a, b) => a.top - b.top);
      const computed = getComputedStyle(selected[0]);
      const visibleStart = (() => {
        if (!probe.visibleToken) return null;
        for (const element of selected) {
          const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
          let node;
          while ((node = walker.nextNode())) {
            const offset = (node.textContent || '').indexOf(probe.visibleToken);
            if (offset < 0) continue;
            const range = document.createRange();
            range.setStart(node, offset);
            range.setEnd(node, offset + 1);
            return rounded(range.getBoundingClientRect().left - rootRect.left);
          }
        }
        return null;
      })();
      const widgetBuffer = selected[0].querySelector('.cm-widgetBuffer');
      const styles = Object.fromEntries(styleKeys.map(key => [
        key,
        computed.getPropertyValue(key).trim()
      ]));
      return {
        id: probe.id,
        found: true,
        text: selected.map(element => element.textContent || '').join('\\n'),
        top: rounded(top - rootRect.top),
        bottom: rounded(bottom - rootRect.top),
        left: rounded(left - rootRect.left),
        right: rounded(right - rootRect.left),
        width: rounded(right - left),
        height: rounded(bottom - top),
        lineCount: orderedLines.length,
        lineTops: orderedLines.map(line => rounded(line.top - rootRect.top)),
        lineWidths: orderedLines.map(line => rounded(line.right - line.left)),
        visibleStart,
        widgetBufferCount: selected.reduce(
          (count, element) => count + element.querySelectorAll('.cm-widgetBuffer').length,
          0
        ),
        widgetBufferHeight: rounded(widgetBuffer?.getBoundingClientRect().height || 0),
        widgetBufferFontSize: widgetBuffer ? getComputedStyle(widgetBuffer).fontSize : '',
        styles
      };
    };
    return {
      surface,
      viewportWidth: rounded(window.innerWidth),
      contentHeight: rounded(Math.max(root.scrollHeight, rootRect.height)),
      probes: probes.map(measure)
    };
    """

}
