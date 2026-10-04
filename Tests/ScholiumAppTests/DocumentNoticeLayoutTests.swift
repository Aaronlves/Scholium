import AppKit
import Observation
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Document notice layout", .serialized)
@MainActor
struct DocumentNoticeLayoutTests {
    @Test("Notice actions remain visible with mixed-script messages and visual adaptations", .enabled(if: ScholiumTestEnvironment.providesDisplayEvidence))
    func noticeAdaptation() async throws {
        _ = NSApplication.shared
        for dark in [false, true] {
            for width: CGFloat in [300, 520] {
                var actionFrames: [String: CGRect] = [:]
                func action(_ title: String) -> some View {
                    Button(title) {}
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("noticeFixture")) }) {
                            actionFrames[title] = $0
                        }
                }
                let host = NSHostingView(
                    rootView:
                        VStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                            ScholiumDocumentStatusNotice(
                                "Reference Unavailable", detail: "This source could not be opened. 原文未改变，请重新查找写作参考。", kind: .information
                            ) { action("Dismiss") }
                            ScholiumDocumentStatusNotice(
                                "Autosave Paused", detail: "Your edits remain available. 未保存的编辑仍然保留。", kind: .attention
                            ) { action("Compare Changes") }
                            ScholiumRecoveryNotice(
                                .init(
                                    "Transaction Recovery Required",
                                    message: Text("2 interrupted operations need file-by-file inspection."),
                                    systemImage: "exclamationmark.arrow.triangle.2.circlepath"),
                                region: .workspaceBanner
                            ) { action("Inspect Recovery…") }
                        }
                        .frame(width: width)
                        .padding(8)
                        .coordinateSpace(name: "noticeFixture")
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .environment(
                            \.scholiumVisualEnvironmentOverride,
                            .init(increasedContrast: dark, reduceTransparency: dark, reduceMotion: true))
                )
                let window = NSWindow(
                    contentRect: .init(x: 0, y: 0, width: width + 16, height: 600),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.orderFront(nil)
                defer {
                    window.contentView = nil
                    window.close()
                }
                for _ in 0..<8 {
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(20))
                }
                #expect(actionFrames.count == 3)
                let visibleFrame = CGRect(origin: .zero, size: host.bounds.size)
                for frame in actionFrames.values {
                    #expect(frame.width > 0 && frame.height >= 20)
                    #expect(visibleFrame.insetBy(dx: -1, dy: -1).contains(frame))
                }
                if let output = ProcessInfo.processInfo.environment["SCHOLIUM_NOTICE_SNAPSHOTS"] {
                    let directory = URL(fileURLWithPath: output)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try #require(bitmap.representation(using: .png, properties: [:]))
                        .write(to: directory.appendingPathComponent("notices-\(Int(width))-\(dark ? "dark-adapted" : "light").png"))
                }
            }
        }
    }

    @Test("Notice arrival, growth, and dismissal preserve the retained Document viewport")
    func noticeLifecycleKeepsViewportStable() async throws {
        _ = NSApplication.shared
        let state = NoticeFixtureState()
        let find = DocumentFindPresentationModel()
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let host = NSHostingView(
            rootView: NoticeFixture(state: state, find: find, document: document)
                .transaction {
                    $0.animation = nil
                    $0.disablesAnimations = true
                })
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }

        for size in [NSSize(width: 600, height: 400), NSSize(width: 320, height: 240)] {
            window.setContentSize(size)
            for findIsPresented in [false, true] {
                if findIsPresented {
                    find.presentReplacement()
                } else {
                    find.dismiss()
                }
                for _ in 0..<10 {
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(20))
                }
                let searchField: NSSearchField?
                if findIsPresented {
                    searchField = findField(in: host)
                    #expect(searchField != nil)
                } else {
                    searchField = nil
                }
                let searchFrame = searchField.map { $0.convert($0.bounds, to: host) }
                for count in [0, 1, 12, 1, 0] {
                    state.count = count
                    host.layoutSubtreeIfNeeded()
                    await Task.yield()
                    host.layoutSubtreeIfNeeded()
                    #expect(document.superview != nil)
                    #expect(document.frame.size == size)
                    #expect(document.convert(document.bounds, to: host).origin == .zero)
                    if let searchField, let searchFrame {
                        #expect(findField(in: host) === searchField)
                        let actual = searchField.convert(searchField.bounds, to: host)
                        #expect(abs(actual.minX - searchFrame.minX) < 1)
                        #expect(abs(actual.minY - searchFrame.minY) < 1)
                        #expect(abs(actual.width - searchFrame.width) < 1)
                    }
                }
            }
        }
    }

    private func findField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField,
            field.accessibilityIdentifier() == "scholium.documentFind.query"
        {
            return field
        }
        return view.subviews.lazy.compactMap { findField(in: $0) }.first
    }
}

@Observable
@MainActor
private final class NoticeFixtureState {
    var count = 0
}

private struct NoticeFixture: View {
    let state: NoticeFixtureState
    let find: DocumentFindPresentationModel
    let document: NSView

    var body: some View {
        RetainedDocumentView(document: document)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        DocumentFindOverlay(
                            model: find,
                            allowsReplacement: true,
                            availableWidth: geometry.size.width
                        )
                        GeometryReader { remaining in
                            if state.count > 0 {
                                ScholiumDocumentNoticeStack(availableSize: remaining.size) {
                                    ForEach(0..<state.count, id: \.self) { index in
                                        ScholiumDocumentStatusNotice(
                                            "Synthetic notice \(index)",
                                            detail: "The source remains available. 原文与未保存的编辑仍然保留。",
                                            kind: index == 0 ? .information : .attention
                                        ) {
                                            Button("Retry Refresh") {}
                                            Button("Dismiss") {}
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
    }
}

private struct RetainedDocumentView: NSViewRepresentable {
    let document: NSView

    func makeNSView(context: Context) -> NSView { document }
    func updateNSView(_ view: NSView, context: Context) {}
}
