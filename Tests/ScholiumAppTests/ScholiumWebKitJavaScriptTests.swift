import AppKit
import Foundation
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Cancellable WebKit JavaScript", .serialized)
@MainActor
final class ScholiumWebKitJavaScriptTests {
    enum Entry: String, CaseIterable, Sendable {
        case call, evaluate

        @MainActor
        func cancellable(_ expression: String, in view: WKWebView) async throws -> Any? {
            switch self {
            case .call:
                return try await view.callCancellableJavaScript("return (\(expression));", contentWorld: .page)
            case .evaluate:
                return try await view.evaluateCancellableJavaScript(expression, contentWorld: .page)
            }
        }

        @MainActor
        func sdk(_ expression: String, in view: WKWebView) async throws -> Any? {
            switch self {
            case .call:
                return try await view.callAsyncJavaScript("return (\(expression));", arguments: [:], in: nil, contentWorld: .page)
            case .evaluate:
                return try await view.evaluateJavaScript(expression, in: nil, contentWorld: .page)
            }
        }
    }

    @Test("Nullable results and structured values match the SDK async entry", arguments: Entry.allCases)
    func valueParity(entry: Entry) async throws {
        let fixture = Fixture()
        defer { fixture.stopAndRelease() }
        try await fixture.load()
        let view = try #require(fixture.owner)
        #expect(try await entry.cancellable("undefined", in: view) == nil)
        #expect(try await entry.sdk("undefined", in: view) == nil)
        #expect(try await entry.cancellable("null", in: view) is NSNull)
        #expect(try await entry.sdk("null", in: view) is NSNull)
        for flag in [true, false] {
            let expression = flag ? "true" : "false"
            #expect(try await entry.cancellable(expression, in: view) as? Bool == flag)
            #expect(try await entry.sdk(expression, in: view) as? Bool == flag)
        }

        let unicode = "Cafe\u{301} 中文😀👩‍🔬"
        let expected: [String: Any] = [
            "text": unicode, "enabled": true,
            "nested": ["empty": NSNull(), "flags": [true, false]], "count": 7,
        ]
        let bytes = try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])
        let expression = try #require(String(data: bytes, encoding: .utf8))
        let wrapped = try #require(try await entry.cancellable("(\(expression))", in: view) as? [String: Any])
        let sdk = try #require(try await entry.sdk("(\(expression))", in: view) as? [String: Any])
        for result in [wrapped, sdk] {
            let text = try #require(result["text"] as? String)
            #expect(text.utf8.elementsEqual(unicode.utf8))
            #expect(result["enabled"] as? Bool == true)
            #expect((result["nested"] as? [String: Any])?["empty"] is NSNull)
            #expect(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) == bytes)
        }
    }

    @Test("Async-call arguments retain exact Unicode and Foundation value types")
    func argumentParity() async throws {
        let fixture = Fixture()
        defer { fixture.stopAndRelease() }
        try await fixture.load()
        let view = try #require(fixture.owner)
        let unicode = "Cafe\u{301} 中文😀👩‍🔬"
        let arguments: [String: Any] = ["text": unicode, "payload": ["flag": true, "empty": NSNull()]]
        let body = "return {text, payload};"
        let wrapped = try #require(
            try await view.callCancellableJavaScript(body, arguments: arguments, contentWorld: .page) as? [String: Any])
        let sdk = try #require(
            try await view.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page) as? [String: Any])
        let expected = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        for result in [wrapped, sdk] {
            #expect((result["text"] as? String)?.utf8.elementsEqual(unicode.utf8) == true)
            #expect((result["payload"] as? [String: Any])?["flag"] as? Bool == true)
            #expect((result["payload"] as? [String: Any])?["empty"] is NSNull)
            #expect(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) == expected)
        }
    }

    @Test("Thrown JavaScript errors match the SDK async entry", arguments: Entry.allCases)
    func exceptionParity(entry: Entry) async throws {
        let fixture = Fixture()
        defer { fixture.stopAndRelease() }
        try await fixture.load()
        let view = try #require(fixture.owner)
        let expression = "(() => { throw new Error('Synthetic 中文 exception'); })()"
        let wrapped = (try await capturedError { _ = try await entry.cancellable(expression, in: view) }) as NSError
        let sdk = (try await capturedError { _ = try await entry.sdk(expression, in: view) }) as NSError
        #expect(wrapped.domain == sdk.domain && wrapped.code == sdk.code)
        #expect(wrapped.domain == WKErrorDomain && wrapped.code == WKError.Code.javaScriptExceptionOccurred.rawValue)
        let key = "WKJavaScriptExceptionMessage"
        let message = try #require(wrapped.userInfo[key] as? String)
        #expect(message == sdk.userInfo[key] as? String)
        #expect(message.contains("Synthetic 中文 exception"))
    }

    @Test("A pre-cancelled entry never dispatches JavaScript", arguments: Entry.allCases)
    func preCancelledEntryDoesNotDispatch(entry: Entry) async throws {
        let fixture = Fixture()
        defer { fixture.stopAndRelease() }
        try await fixture.load()
        let observation = CompletionObservation()
        let task = Task<Void, any Error> { @MainActor in
            defer { observation.finishes += 1 }
            guard let view = fixture.owner else { throw FixtureFailure.missingOwner }
            _ = try await entry.cancellable("(window.__cancelledDispatch = true)", in: view)
            observation.returnedNormally = true
        }
        // The MainActor cannot enter this new task before cancellation below.
        task.cancel()
        try await waitUntil("The pre-cancelled task did not finish") { observation.finishes == 1 }
        try await requireCancellation(task)
        let view = try #require(fixture.owner)
        #expect(try await view.evaluateJavaScript("window.__cancelledDispatch === undefined", in: nil, contentWorld: .page) as? Bool == true)
        #expect(!observation.returnedNormally)
    }

    @Test("Cancelling a held promise finishes before releasing its native WebView owner")
    func cancelledPromiseReleasesWebView() async throws {
        let fixture = Fixture()
        defer { fixture.stopAndRelease() }
        try await fixture.load()
        let observation = CompletionObservation()
        let task = fixture.startHeldCall(observation: observation)
        defer { task.cancel() }
        do {
            try await fixture.waitForEnteredPromise()
            task.cancel()
            try await waitUntil("The held JavaScript task ignored cancellation") { observation.finishes == 1 }
            try await requireCancellation(task)
            #expect(!observation.returnedNormally)
            // The call has already finished. Now remove the only test-owned
            // strong WebView reference while its JavaScript promise stays held.
            fixture.releaseOwner()
            try await waitUntil("The cancelled JavaScript call still owns its WebView") { fixture.nativeOwnerHasReleased }
            #expect(observation.finishes == 1)
        } catch {
            // Failure cleanup is deliberately outside the passing release
            // oracle. Never resolve or stopLoading to establish success.
            await fixture.releaseGateForCleanup()
            fixture.stopAndRelease()
            throw error
        }
    }

    @Test("A physical result arriving after cancellation cannot resume the task twice", arguments: [false, true])
    func lateCallbackIsHarmless(rejects: Bool) async throws {
        let fixture = Fixture()
        defer { fixture.stopAndRelease() }
        try await fixture.load()
        let observation = CompletionObservation()
        let task = fixture.startHeldCall(observation: observation, rejects: rejects)
        defer { task.cancel() }
        do {
            try await fixture.waitForEnteredPromise()
            task.cancel()
            try await waitUntil("The retained-page JavaScript task ignored cancellation") { observation.finishes == 1 }
            try await requireCancellation(task)
            try await fixture.releaseGateAndObserveSettlement()
            // Settlement is observed in JavaScript and followed by fresh SDK
            // async round trips on the retained page, rather than a timed yield.
            try await requireCancellation(task)
            #expect(observation.finishes == 1 && !observation.returnedNormally)
        } catch {
            await fixture.releaseGateForCleanup()
            throw error
        }
    }

    private func capturedError(_ operation: @MainActor () async throws -> Void) async throws -> any Error {
        do { try await operation() } catch { return error }
        Issue.record("JavaScript unexpectedly succeeded")
        throw FixtureFailure.missingError
    }

    private func requireCancellation(_ task: Task<Void, any Error>) async throws {
        let error = try await capturedError { try await task.value }
        #expect(error is CancellationError)
    }

    private func waitUntil(_ message: String, _ condition: @MainActor () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(try await condition()) {
            try #require(ContinuousClock.now < deadline, Comment(rawValue: message))
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private enum FixtureFailure: Error { case missingOwner, missingError }

    @MainActor
    private final class CompletionObservation {
        var finishes = 0
        var returnedNormally = false
    }

    @MainActor
    private final class Fixture {
        var owner: WKWebView?
        private weak var witness: WKWebView?

        init() {
            _ = NSApplication.shared
            owner = autoreleasepool {
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                return WKWebView(frame: .zero, configuration: configuration)
            }
            witness = owner
        }

        var nativeOwnerHasReleased: Bool { autoreleasepool { witness == nil } }

        func load() async throws {
            guard let view = owner else { throw FixtureFailure.missingOwner }
            view.loadHTMLString("<html><body id='cancellable-javascript'>Synthetic fixture</body></html>", baseURL: nil)
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while (try await view.callAsyncJavaScript(
                "return document.body?.id === 'cancellable-javascript';", arguments: [:], in: nil, contentWorld: .page)) as? Bool != true
            {
                try #require(ContinuousClock.now < deadline, "The synthetic JavaScript page did not load")
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func startHeldCall(observation: CompletionObservation, rejects: Bool = false) -> Task<Void, any Error> {
            Task { @MainActor [weak self] in
                defer { observation.finishes += 1 }
                guard let view = self?.owner else { throw FixtureFailure.missingOwner }
                _ = try await view.callCancellableJavaScript(
                    """
                    const state = window.__heldCall = {settled: false, release: null};
                    try {
                        return await new Promise((resolve, reject) => {
                            state.release = () => rejectLate
                                ? reject(new Error('Synthetic late rejection'))
                                : resolve({text: 'Late 中文 result', flag: true});
                        });
                    } finally { state.settled = true; }
                    """,
                    arguments: ["rejectLate": rejects], contentWorld: .page)
                observation.returnedNormally = true
            }
        }

        func waitForEnteredPromise() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !(try await promiseHasEntered()) {
                try #require(ContinuousClock.now < deadline, "The actual JavaScript call did not enter its promise gate")
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        private func promiseHasEntered() async throws -> Bool {
            guard let view = owner else { return false }
            return try await view.callAsyncJavaScript(
                "return typeof window.__heldCall?.release === 'function' && !window.__heldCall.settled;",
                arguments: [:], in: nil, contentWorld: .page) as? Bool == true
        }

        func releaseGateAndObserveSettlement() async throws {
            guard let view = owner else { throw FixtureFailure.missingOwner }
            _ = try await view.callAsyncJavaScript("window.__heldCall.release();", arguments: [:], in: nil, contentWorld: .page)
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while (try await view.callAsyncJavaScript(
                "return window.__heldCall.settled;", arguments: [:], in: nil, contentWorld: .page)) as? Bool != true
            {
                try #require(ContinuousClock.now < deadline, "The old physical JavaScript invocation did not settle")
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(try await view.evaluateJavaScript("document.body.id", in: nil, contentWorld: .page) as? String == "cancellable-javascript")
        }

        func releaseGateForCleanup() async {
            // A failed release assertion may already have cleared owner. The
            // weak witness permits cleanup without owning the passing lifetime.
            let remaining = autoreleasepool { owner ?? witness }
            if let remaining {
                _ = try? await remaining.callAsyncJavaScript("window.__heldCall?.release?.();", arguments: [:], in: nil, contentWorld: .page)
            }
        }

        func releaseOwner() { autoreleasepool { owner = nil } }

        func stopAndRelease() {
            autoreleasepool {
                owner?.stopLoading()
                owner = nil
            }
        }
    }
}
