#if DEBUG
import AppKit
import Foundation
import WebKit

@MainActor
extension MarkdownEditorSession {
    func testingScrollEditor(by delta: Double) async throws -> Double {
        guard let webView else { throw SessionError.unavailable }
        let result = try await webView.callAsyncJavaScript(
            """
            const scroller = document.querySelector('.cm-scroller');
            if (!scroller) return null;
            const before = scroller.scrollTop;
            scroller.scrollTop = before + delta;
            scroller.dispatchEvent(new Event('scroll'));
            await new Promise(resolve => {
              let settled = false;
              const finish = () => {
                if (settled) return;
                settled = true;
                resolve();
              };
              requestAnimationFrame(() => requestAnimationFrame(finish));
              setTimeout(finish, 100);
            });
            return scroller.scrollTop - before;
            """,
            arguments: ["delta": delta],
            in: nil,
            contentWorld: .page
        )
        guard let applied = (result as? NSNumber)?.doubleValue else {
            throw SessionError.invalidResult
        }
        return applied
    }

    func testingClickFirstCalloutText(_ requestedText: String) async throws {
        guard let webView else { throw SessionError.unavailable }
        let result = try await webView.callAsyncJavaScript(
            """
            for (const root of document.querySelectorAll('.cm-live-callout-widget.scholium-callout')) {
                const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                    const index = node.textContent?.indexOf(requestedText) ?? -1;
                    if (index < 0) continue;
                    const range = document.createRange();
                    range.setStart(node, index);
                    range.setEnd(node, Math.min(node.length, index + Math.max(1, requestedText.length)));
                    const rect = range.getBoundingClientRect();
                    (node.parentElement || root).dispatchEvent(new MouseEvent('mousedown', {
                        bubbles: true,
                        cancelable: true,
                        clientX: rect.left + Math.min(8, rect.width / 2),
                        clientY: (rect.top + rect.bottom) / 2
                    }));
                    const revealedOnMouseDown = !root.isConnected
                        && document.querySelectorAll('.cm-line.cm-live-callout').length > 0;
                    window.dispatchEvent(new MouseEvent('mouseup', {bubbles: true}));
                    return revealedOnMouseDown;
                }
            }
            return false;
            """,
            arguments: ["requestedText": requestedText],
            in: nil,
            contentWorld: .page
        )
        guard result as? Bool == true else { throw SessionError.invalidResult }
    }

    func testingClickFirstFootnoteReference() async throws {
        guard let webView else { throw SessionError.unavailable }
        let result = try await webView.callAsyncJavaScript(
            """
            const marker = document.querySelector('.cm-live-footnote-reference-widget .footnote-reference');
            if (!marker) return null;
            marker.scrollIntoView({block: 'center', behavior: 'auto'});
            const rect = marker.getBoundingClientRect();
            return {
              x: (rect.left + rect.right) / 2,
              y: (rect.top + rect.bottom) / 2
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard let position = result as? [String: Any],
              let x = position["x"] as? Double,
              let y = position["y"] as? Double else {
            throw SessionError.invalidResult
        }
        try await testingClickPagePoint(x: x, y: y, in: webView)
    }

    func testingClickFirstTableCell() async throws {
        guard let webView else { throw SessionError.unavailable }
        let scrolled = try await webView.callAsyncJavaScript(
            """
            const cell = document.querySelector('.cm-live-table-widget th, .cm-live-table-widget td');
            if (!cell) return false;
            cell.scrollIntoView({block: 'center', behavior: 'auto'});
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard scrolled as? Bool == true else { throw SessionError.invalidResult }
        // scrollIntoView can trigger a CodeMirror viewport measurement. Read
        // the hit point in the following settled layout turn rather than from
        // the pre-scroll rectangle returned by the same JavaScript turn.
        try await Task.sleep(for: .milliseconds(100))
        let activated = try await webView.callAsyncJavaScript(
            """
            const cell = document.querySelector('.cm-live-table-widget th, .cm-live-table-widget td');
            if (!cell) return false;
            const rect = cell.getBoundingClientRect();
            const clientX = rect.left + Math.min(12, rect.width / 2);
            const clientY = (rect.top + rect.bottom) / 2;
            cell.dispatchEvent(new MouseEvent('mousedown', {
                button: 0,
                clientX,
                clientY,
                bubbles: true,
                cancelable: true
            }));
            cell.dispatchEvent(new MouseEvent('mouseup', {
                button: 0,
                clientX,
                clientY,
                bubbles: true,
                cancelable: true
            }));
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard activated as? Bool == true else { throw SessionError.invalidResult }
    }

    func testingClickVisibleText(_ requestedText: String) async throws {
        guard let webView else { throw SessionError.unavailable }
        let scrolled = try await webView.callAsyncJavaScript(
            """
            for (const root of document.querySelectorAll('.cm-line')) {
                if (root.textContent?.includes(requestedText)) {
                    root.scrollIntoView({block: 'center', behavior: 'auto'});
                    return true;
                }
            }
            return false;
            """,
            arguments: ["requestedText": requestedText],
            in: nil,
            contentWorld: .page
        )
        guard scrolled as? Bool == true else { throw SessionError.invalidResult }
        try await Task.sleep(for: .milliseconds(100))
        let result = try await webView.callAsyncJavaScript(
            """
            for (const root of document.querySelectorAll('.cm-line')) {
                const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                    const index = node.textContent?.indexOf(requestedText) ?? -1;
                    if (index < 0) continue;
                    const range = document.createRange();
                    range.setStart(node, index);
                    range.setEnd(node, Math.min(node.length, index + Math.max(1, requestedText.length)));
                    const rect = range.getBoundingClientRect();
                    return {x: (rect.left + rect.right) / 2, y: (rect.top + rect.bottom) / 2};
                }
            }
            return null;
            """,
            arguments: ["requestedText": requestedText],
            in: nil,
            contentWorld: .page
        )
        guard let position = result as? [String: Any],
              let x = position["x"] as? Double,
              let y = position["y"] as? Double else {
            throw SessionError.invalidResult
        }
        try await testingClickPagePoint(x: x, y: y, in: webView)
    }

    func testingModifiedClickVisibleText(
        _ requestedText: String,
        modifierFlags: NSEvent.ModifierFlags
    ) async throws {
        guard let webView else { throw SessionError.unavailable }
        let result = try await webView.callAsyncJavaScript(
            """
            for (const root of document.querySelectorAll('.cm-line, .cm-live-callout-widget')) {
                const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                    const index = node.textContent?.indexOf(requestedText) ?? -1;
                    if (index < 0) continue;
                    const range = document.createRange();
                    range.setStart(node, index);
                    range.setEnd(node, Math.min(node.length, index + Math.max(1, requestedText.length)));
                    const rect = range.getBoundingClientRect();
                    const init = {
                        view: window,
                        bubbles: true,
                        cancelable: true,
                        clientX: (rect.left + rect.right) / 2,
                        clientY: (rect.top + rect.bottom) / 2,
                        button: 0,
                        ctrlKey,
                        metaKey
                    };
                    const target = node.parentElement || root;
                    target.dispatchEvent(new MouseEvent('mousedown', {...init, buttons: 1}));
                    document.dispatchEvent(new MouseEvent('mouseup', {...init, buttons: 0}));
                    target.dispatchEvent(new MouseEvent('click', {...init, buttons: 0}));
                    return true;
                }
            }
            return false;
            """,
            arguments: [
                "requestedText": requestedText,
                "ctrlKey": modifierFlags.contains(.control),
                "metaKey": modifierFlags.contains(.command),
            ],
            in: nil,
            contentWorld: .page
        )
        guard result as? Bool == true else { throw SessionError.invalidResult }
    }

    func testingTripleClickVisibleText(_ requestedText: String) async throws {
        guard let webView else { throw SessionError.unavailable }
        let position = try await testingVisibleTextPoint(requestedText, in: webView)
        try await testingClickPagePoint(
            x: position.x,
            y: position.y,
            in: webView,
            clickCount: 3
        )
    }

    func testingDragSelectionProjection(
        from startText: String,
        to endText: String,
        lineContaining lineText: String
    ) async throws -> TestingPointerProjectionResult {
        guard let webView else { throw SessionError.unavailable }
        let rawResult = try await webView.callAsyncJavaScript(
            """
            const locate = requested => {
                for (const root of document.querySelectorAll('.cm-line, .cm-live-callout-widget')) {
                    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                    let node;
                    while ((node = walker.nextNode())) {
                        const index = node.textContent?.indexOf(requested) ?? -1;
                        if (index < 0) continue;
                        const range = document.createRange();
                        range.setStart(node, index);
                        range.setEnd(node, Math.min(node.length, index + Math.max(1, requested.length)));
                        const rect = range.getBoundingClientRect();
                        return {
                            target: node.parentElement || root,
                            x: (rect.left + rect.right) / 2,
                            y: (rect.top + rect.bottom) / 2
                        };
                    }
                }
                return null;
            };
            const lineTextValue = () => Array.from(document.querySelectorAll('.cm-line'))
                .find(line => line.textContent?.includes(lineText))?.textContent || '';
            const start = locate(startText);
            const end = locate(endText);
            if (!start || !end) return null;
            start.target.dispatchEvent(new MouseEvent('mousedown', {
                view: window,
                bubbles: true,
                cancelable: true,
                clientX: start.x,
                clientY: start.y,
                button: 0,
                buttons: 1,
                detail: 1
            }));
            document.dispatchEvent(new MouseEvent('mousemove', {
                view: window,
                bubbles: true,
                cancelable: true,
                clientX: end.x,
                clientY: end.y,
                button: 0,
                buttons: 1,
                detail: 1
            }));
            const duringDragLineText = lineTextValue();
            const toolbarHiddenDuringDrag = document.getElementById(
                'scholium-selection-actions'
            )?.hidden !== false;
            document.dispatchEvent(new MouseEvent('mouseup', {
                view: window,
                bubbles: true,
                cancelable: true,
                clientX: end.x,
                clientY: end.y,
                button: 0,
                buttons: 0,
                detail: 1
            }));
            await Promise.resolve();
            const afterMouseUpLineText = lineTextValue();
            const toolbarVisibleAfterMouseUp = document.getElementById(
                'scholium-selection-actions'
            )?.hidden === false;
            return {
                duringDragLineText,
                afterMouseUpLineText,
                toolbarHiddenDuringDrag,
                toolbarVisibleAfterMouseUp
            };
            """,
            arguments: [
                "startText": startText,
                "endText": endText,
                "lineText": lineText,
            ],
            in: nil,
            contentWorld: .page
        )
        guard let payload = rawResult as? [String: Any],
              let during = payload["duringDragLineText"] as? String,
              let after = payload["afterMouseUpLineText"] as? String,
              let hiddenDuring = payload["toolbarHiddenDuringDrag"] as? Bool,
              let visibleAfter = payload["toolbarVisibleAfterMouseUp"] as? Bool else {
            throw SessionError.invalidResult
        }
        return TestingPointerProjectionResult(
            duringDragLineText: during,
            afterMouseUpLineText: after,
            toolbarHiddenDuringDrag: hiddenDuring,
            toolbarVisibleAfterMouseUp: visibleAfter
        )
    }

    func testingClickBlankLine(between precedingText: String, and followingText: String) async throws {
        guard let webView else { throw SessionError.unavailable }
        let scrolled = try await webView.callAsyncJavaScript(
            """
            const lines = Array.from(document.querySelectorAll('.cm-line'));
            const preceding = lines.findIndex(line => line.textContent?.includes(precedingText));
            const following = lines.findIndex((line, index) =>
                index > preceding && line.textContent?.includes(followingText));
            if (preceding < 0 || following <= preceding) return false;
            const blank = lines.slice(preceding + 1, following)
                .find(line => line.classList.contains('cm-live-blank-line'));
            if (!blank) return false;
            blank.scrollIntoView({block: 'center', behavior: 'auto'});
            return true;
            """,
            arguments: [
                "precedingText": precedingText,
                "followingText": followingText,
            ],
            in: nil,
            contentWorld: .page
        )
        guard scrolled as? Bool == true else { throw SessionError.invalidResult }
        try await Task.sleep(for: .milliseconds(100))
        let result = try await webView.callAsyncJavaScript(
            """
            const lines = Array.from(document.querySelectorAll('.cm-line'));
            const preceding = lines.findIndex(line => line.textContent?.includes(precedingText));
            const following = lines.findIndex((line, index) =>
                index > preceding && line.textContent?.includes(followingText));
            const blank = lines.slice(preceding + 1, following)
                .find(line => line.classList.contains('cm-live-blank-line'));
            if (!blank) return null;
            const rect = blank.getBoundingClientRect();
            return {
                x: rect.left + Math.min(12, Math.max(1, rect.width / 2)),
                y: (rect.top + rect.bottom) / 2
            };
            """,
            arguments: [
                "precedingText": precedingText,
                "followingText": followingText,
            ],
            in: nil,
            contentWorld: .page
        )
        guard let position = result as? [String: Any],
              let x = position["x"] as? Double,
              let y = position["y"] as? Double else {
            throw SessionError.invalidResult
        }
        try await testingClickPagePoint(x: x, y: y, in: webView)
    }

    private func testingVisibleTextPoint(
        _ requestedText: String,
        in webView: WKWebView
    ) async throws -> (x: Double, y: Double) {
        let result = try await webView.callAsyncJavaScript(
            """
            for (const root of document.querySelectorAll('.cm-line, .cm-live-callout-widget')) {
                const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                    const index = node.textContent?.indexOf(requestedText) ?? -1;
                    if (index < 0) continue;
                    const range = document.createRange();
                    range.setStart(node, index);
                    range.setEnd(node, Math.min(node.length, index + Math.max(1, requestedText.length)));
                    const rect = range.getBoundingClientRect();
                    return {x: (rect.left + rect.right) / 2, y: (rect.top + rect.bottom) / 2};
                }
            }
            return null;
            """,
            arguments: ["requestedText": requestedText],
            in: nil,
            contentWorld: .page
        )
        guard let position = result as? [String: Any],
              let x = position["x"] as? Double,
              let y = position["y"] as? Double else {
            throw SessionError.invalidResult
        }
        return (x, y)
    }

    private func testingClickPagePoint(
        x: Double,
        y: Double,
        in webView: WKWebView,
        modifierFlags: NSEvent.ModifierFlags = [],
        clickCount: Int = 1
    ) async throws {
        guard let window = webView.window else { throw SessionError.invalidResult }
        try await Task.sleep(for: .milliseconds(100))

        let webViewPoint = NSPoint(
            x: x,
            y: webView.isFlipped ? y : webView.bounds.height - y
        )
        let windowPoint = webView.convert(webViewPoint, to: nil)
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: modifierFlags,
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        ), let mouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: windowPoint,
            modifierFlags: modifierFlags,
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 0
        ) else {
            throw SessionError.invalidResult
        }
        webView.mouseDown(with: mouseDown)
        webView.mouseUp(with: mouseUp)
    }

    func testingPressArrow(_ key: String, shiftKey: Bool = false) async throws {
        guard let webView else { throw SessionError.unavailable }
        let result = try await webView.callAsyncJavaScript(
            """
            const content = document.querySelector('.cm-content');
            if (!content) return false;
            const event = new KeyboardEvent('keydown', {
                key,
                shiftKey,
                bubbles: true,
                cancelable: true
            });
            content.dispatchEvent(event);
            return event.defaultPrevented;
            """,
            arguments: ["key": key, "shiftKey": shiftKey],
            in: nil,
            contentWorld: .page
        )
        guard result as? Bool == true else { throw SessionError.invalidResult }
    }

    func testingPressBackspace() async throws {
        guard let webView else { throw SessionError.unavailable }
        let result = try await webView.callAsyncJavaScript(
            """
            const content = document.querySelector('.cm-content');
            if (!content) return false;
            const event = new KeyboardEvent('keydown', {
                key: 'Backspace',
                code: 'Backspace',
                keyCode: 8,
                which: 8,
                bubbles: true,
                cancelable: true
            });
            content.dispatchEvent(event);
            return event.defaultPrevented;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard result as? Bool == true else { throw SessionError.invalidResult }
    }

    func testingPressEnter() async throws {
        guard let webView else { throw SessionError.unavailable }
        let result = try await webView.callAsyncJavaScript(
            """
            const content = document.querySelector('.cm-content');
            if (!content) return false;
            const event = new KeyboardEvent('keydown', {
                key: 'Enter',
                code: 'Enter',
                keyCode: 13,
                which: 13,
                bubbles: true,
                cancelable: true
            });
            content.dispatchEvent(event);
            return event.defaultPrevented;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard result as? Bool == true else { throw SessionError.invalidResult }
    }

    func testingDispatchCompositionEvent(_ type: String) async throws {
        guard let webView, type == "compositionstart" || type == "compositionend" else {
            throw SessionError.invalidResult
        }
        let result = try await webView.callAsyncJavaScript(
            """
            const content = document.querySelector('.cm-content');
            if (!content) return false;
            return content.dispatchEvent(new CompositionEvent(type, {
                bubbles: true,
                cancelable: false,
                data: ''
            }));
            """,
            arguments: ["type": type],
            in: nil,
            contentWorld: .page
        )
        guard result as? Bool == true else { throw SessionError.invalidResult }
    }

    func testingApplyScrollAnchor(_ anchor: EditorScrollAnchor) async throws {
        guard isReady, isLoaded, let webView,
              let wireAnchor = wireAnchor(from: anchor, in: checkedSource) else {
            throw SessionError.invalidResult
        }
        pendingScrollAnchor = anchor
        pendingScrollFraction = anchor.fallbackFraction
        _ = try await send(.setScrollAnchor(wireAnchor), in: webView)
    }

    func testingApplyScrollFraction(_ fraction: Double) async throws {
        guard isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let normalized = min(1, max(0, fraction))
        pendingScrollFraction = normalized
        pendingScrollAnchor = nil
        _ = try await send(.setScrollFraction(normalized), in: webView)
    }

    var testingRetainedScrollFraction: Double? { pendingScrollFraction }
    var testingRetainedScrollAnchor: EditorScrollAnchor? { pendingScrollAnchor }
}
#endif
