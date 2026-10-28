import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    @Test("Separate title panel keeps the first body row inside the viewport")
    func separateTitleRetainsBodyViewport() async throws {
        let harness = EditorHarness(
            documentTitle: "Short title", source: "Lead.\n\n# Body\n\nAfter.",
            laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.waitUntilNativeInputIsEnabled()
        let geometry = try #require(try await harness.callPageJavaScript(
            """
            await document.fonts.ready;
            const scroller = document.querySelector('.cm-scroller');
            const container = document.querySelector('.scholium-note-title-container');
            const body = document.querySelector('.cm-content');
            return {bodyTop: body.getBoundingClientRect().top,
              viewportBottom: scroller.getBoundingClientRect().bottom,
              containerHeight: container.getBoundingClientRect().height,
              classes: container.className, computedHeight: getComputedStyle(container).height};
            """) as? [String: Any])
        let bodyTop = try #require((geometry["bodyTop"] as? NSNumber)?.doubleValue)
        let viewportBottom = try #require((geometry["viewportBottom"] as? NSNumber)?.doubleValue)
        #expect(bodyTop < viewportBottom, Comment(rawValue: "Title geometry: \(geometry)"))
        await harness.closeAndDrain()
    }

    @Test(
        "CodeMirror pointer selection targets exact prose after inactive compact citations",
        arguments: [MarkdownEditorMode.livePreview, .source], [false, true])
    func pointerSelectionAfterCompactCitations(mode: MarkdownEditorMode, usesCRLF: Bool) async throws {
        let newline = usesCRLF ? "\r\n" : "\n"
        let firstID = "c3edba04340f34a528a68879ad3b91332"
        let secondID = "c63545913cd664844824449d9d5516a3c"
        let label = #"\(Schroeder\, 2007\)"#
        let source = [
            "\u{FEFF}Lead 中文 😀 e\u{301}.", "",
            "First: [\(label)](cite:\(firstID))",
            "Second: [\(label)](cite:\(secondID))", "",
            "Bibliography:", "", "Tail without newline",
        ].joined(separator: newline)
        let code = #"ITEM CSL_CITATION {"citationItems":[{"id":7}]}"#
        let data = ZoteroCitationData(
            fields: [firstID, secondID].map {
                .init(id: $0, kind: .citation, code: code, text: "(Schroeder, 2007)")
            },
            acceptedFields: [firstID, secondID].map { .init(id: $0, code: code) })
        let snapshot = ZoteroCitationSnapshot(
            noteID: UUID(), vaultID: UUID(), revision: DocumentFingerprint(content: "Disposable companion"),
            sourceFingerprint: DocumentFingerprint(content: source), data: data, status: .available)
        let harness = EditorHarness(
            documentTitle: "Selection fixture", source: source, citationSnapshot: snapshot,
            initialMode: mode, initialSourceRange: source.utf16.count..<source.utf16.count,
            laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.waitUntilNativeInputIsEnabled()
        try await harness.session.focusAndWait()

        if mode == .livePreview {
            let textServices = try #require(try await harness.callPageJavaScript(
                """
                const content = document.querySelector('.cm-content');
                const title = document.querySelector('.scholium-note-title-input');
                const buffers = [...content.querySelectorAll('.cm-widgetBuffer')];
                return {
                  separateTitle: !!title && !content.contains(title)
                    && content.parentElement.contains(title),
                  bufferCount: buffers.length,
                  hiddenBuffersRetainGeometry: buffers.every(buffer => {
                    const style = getComputedStyle(buffer);
                    return style.visibility === 'hidden' && style.display !== 'none'
                      && buffer.getBoundingClientRect().height > 0;
                  })
                };
                """) as? [String: Any])
            // Native red/green probes established that a nested title and
            // exposed zero-source image buffers distort WebKit's flat AX
            // ranges. Keep those objects out of the body text service while
            // retaining CodeMirror's browser-caret anchors and geometry.
            #expect(textServices["separateTitle"] as? Bool == true)
            #expect((textServices["bufferCount"] as? Int ?? 0) >= 4)
            #expect(textServices["hiddenBuffersRetainGeometry"] as? Bool == true)
        }

        let target = "Bibliography:"
        let exactRange = (source as NSString).range(of: target)
        let offsets = EditorSourceOffsetMap(source: source)
        let from = try #require(offsets.editorUTF16Offset(forSourceUTF16Offset: exactRange.location))
        let to = try #require(offsets.editorUTF16Offset(forSourceUTF16Offset: exactRange.location + exactRange.length))
        let probe = try #require(
            try await harness.callPageJavaScript(
                """
                const content = document.querySelector('.cm-content');
                await document.fonts.ready;
                const projectedCitations = content.querySelectorAll('.cm-live-citation').length;
                const concealedDestinations = !content.textContent.includes('cite:');
                const point = end => {
                  for (const line of content.querySelectorAll('.cm-line')) {
                    const index = line.textContent.indexOf(target);
                    if (index < 0) continue;
                    let offset = index + (end ? target.length - 1 : 0);
                    const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
                    let node;
                    while ((node = walker.nextNode())) {
                      if (offset >= node.length) { offset -= node.length; continue; }
                      const range = document.createRange();
                      range.setStart(node, offset); range.setEnd(node, offset + 1);
                      const box = range.getBoundingClientRect();
                      if (!box.width || !box.height) break;
                      return {x: end ? box.right - 0.2 : box.left + 0.2,
                        y: box.top + box.height / 2, target: node.parentElement};
                    }
                  }
                  throw new Error('Fixture selection text has no glyph geometry');
                };
                const start = point(false), end = point(true);
                start.target.dispatchEvent(new MouseEvent('mousedown', {bubbles: true, cancelable: true,
                  button: 0, buttons: 1, detail: 1, clientX: start.x, clientY: start.y}));
                document.dispatchEvent(new MouseEvent('mousemove', {bubbles: true, cancelable: true,
                  button: 0, buttons: 1, clientX: end.x, clientY: end.y}));
                document.dispatchEvent(new MouseEvent('mouseup', {bubbles: true, cancelable: true,
                  button: 0, buttons: 0, clientX: end.x, clientY: end.y}));
                await Promise.resolve();
                return {selected: window.getSelection()?.toString(), projectedCitations, concealedDestinations};
                """, arguments: ["target": target]) as? [String: Any])
        #expect(probe["selected"] as? String == target, Comment(rawValue: "Pointer selection probe: \(probe)"))
        if mode == .livePreview {
            #expect(probe["projectedCitations"] as? Int == 2)
            #expect(probe["concealedDestinations"] as? Bool == true)
        }
        try await harness.waitUntilSelection(anchor: from, head: to, stage: "pointer range after compact citations")
        #expect(try await harness.callPageJavaScript("return window.getSelection()?.toString();") as? String == target)
        #expect((harness.session.checkedSource as NSString).substring(with: exactRange) == target)
        #expect(!harness.session.isDirty)

        // This exercises CodeMirror's actual pointer handlers, without
        // interpreting rendered/AX string indices as source positions. Paste
        // remains bound to the checked pointer range; no unfocused browser
        // execCommand or fabricated document.hasFocus is involved.
        try await harness.session.pasteClipboard(
            plainText: "References:", selections: [.init(anchor: from, head: to)])
        let expected = (source as NSString).replacingCharacters(in: exactRange, with: "References:")
        try await harness.waitUntilText(expected, stage: "replacement of only the selected prose")
        #expect(Data(try await harness.session.currentText().utf8) == Data(expected.utf8))
        #expect(harness.session.checkedCitationData == data)

        _ = try await harness.callPageJavaScript(
            """
            document.querySelector('.cm-content').dispatchEvent(new KeyboardEvent('keydown', {
              key: 'z', code: 'KeyZ', keyCode: 90, which: 90, metaKey: true,
              bubbles: true, cancelable: true
            }));
            """)
        try await harness.waitUntilText(source, stage: "exact Undo after pointer prose selection")
        #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
        #expect(harness.session.checkedCitationData == data)

        // Enter and leave the concealed destination's closing boundary using
        // CodeMirror's keyboard path, then insert adjacent prose. Hidden
        // buffers must continue to anchor the caret without changing fields.
        let destination = (source as NSString).range(of: "(cite:\(firstID))")
        let sourceEnd = destination.location + destination.length
        let editorEnd = try #require(offsets.editorUTF16Offset(forSourceUTF16Offset: sourceEnd))
        harness.revealEditorRange(fromUTF16: editorEnd, toUTF16: editorEnd)
        try await harness.waitUntilSelection(head: editorEnd, stage: "citation closing boundary")
        try await harness.session.testingPressArrow("ArrowLeft")
        try await harness.waitUntilSelection(head: editorEnd - 1, stage: "enter citation closing syntax")
        try await harness.session.testingPressArrow("ArrowRight")
        try await harness.waitUntilSelection(head: editorEnd, stage: "leave citation closing syntax")
        try await harness.session.perform(.pastePlain, argument: "!")
        let adjacent = (source as NSString).replacingCharacters(in: NSRange(location: sourceEnd, length: 0), with: "!")
        try await harness.waitUntilText(adjacent, stage: "insert prose adjacent to citation")
        #expect(Data(try await harness.session.currentText().utf8) == Data(adjacent.utf8))
        #expect(harness.session.checkedCitationData == data)
        _ = try await harness.callPageJavaScript(
            "document.querySelector('.cm-content').dispatchEvent(new KeyboardEvent('keydown', {key: 'z', code: 'KeyZ', metaKey: true, bubbles: true, cancelable: true}));")
        try await harness.waitUntilText(source, stage: "Undo adjacent prose insertion")
        #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
        #expect(harness.session.checkedCitationData == data)
        await harness.closeAndDrain()
    }
}
