import AppKit
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

/// Synthetic native measurements of the same process owner used in Chat.
/// This is mechanism evidence, not a release timing threshold.
@Suite("Chat activity browsing", .serialized)
@MainActor
struct AgentChatActivityBrowsingTests {
    private final class WeakRowView {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private final class Model: ObservableObject {
        @Published var messages: [AgentChatMessage]
        @Published var expansion: Bool?
        @Published var forceExpanded = false
        @Published var isActive = false
        @Published var toolGroupExpansions: [String: Bool] = [:]
        var mountedRows: Set<String> = []
        var rowMountCounts: [String: Int] = [:]
        var nativeRows: [String: WeakRowView] = [:]
        var mountedCommentary: Set<String> = []
        var parentMounted = false
        init(expansion: Bool?, status: AgentChatActivity.Status = .failed) {
            self.expansion = expansion
            messages = (0..<400).map { index in
                AgentChatMessage(
                    id: "activity-\(index)", role: .operation, text: "",
                    activity: .init(
                        kind: .tool, status: status, source: .runtime,
                        subject: "Synthetic attachment \(index)", detail: String(repeating: "Synthetic retained output. ", count: 600)))
            }
        }
    }

    private struct RowProbe: NSViewRepresentable {
        let mounted: (NSView) -> Void
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            mounted(view)
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {}
    }

    private struct Fixture: View {
        @ObservedObject var model: Model
        var body: some View {
            AgentChatProcessView(
                messages: model.messages, window: .constant(.init()),
                forceExpanded: model.forceExpanded,
                isActive: model.isActive,
                status: .init(state: .working),
                revealedActivityID: model.forceExpanded ? model.messages.last?.id : nil,
                animates: false,
                userExpansion: $model.expansion, toolGroupExpansions: $model.toolGroupExpansions
            ) { message in
                if let activity = message.activity {
                    DisclosureGroup {
                        AgentChatActivityDetails(activity: activity)
                    } label: {
                        AgentChatActivitySummary(activity: activity, noteTarget: nil, openNote: { _ in })
                    }
                    .disclosureGroupStyle(AgentChatDisclosureStyle(animates: false, symbol: activity.kind.symbol))
                    .background(
                        RowProbe { view in
                            model.mountedRows.insert(message.id)
                            model.rowMountCounts[message.id, default: 0] += 1
                            model.nativeRows[message.id] = WeakRowView(view)
                        })
                } else {
                    Text(message.text).background(RowProbe { _ in model.mountedCommentary.insert(message.id) })
                }
            }
            .background(RowProbe { _ in model.parentMounted = true })
            .padding(12)
        }
    }

    @Test("Live commentary stays readable while consecutive tool runs independently fold")
    func liveCommentaryAndToolRuns() async throws {
        let model = Model(expansion: nil, status: .running)
        let tools = Array(model.messages.prefix(4))
        model.messages = [
            .init(id: "before", role: .assistant, text: "Public progress before tools"),
            tools[0], tools[1],
            .init(id: "between", role: .assistant, text: "Public progress between tools"),
            tools[2], tools[3],
            .init(id: "after", role: .assistant, text: "Public progress after tools"),
        ]
        model.isActive = true
        let host = NSHostingView(rootView: Fixture(model: model))
        let window = window(host)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)
        #expect(model.mountedCommentary == ["before", "between", "after"])
        #expect(model.mountedRows.isEmpty)
        let foldedToolsHeight = host.fittingSize.height
        model.toolGroupExpansions["tools:activity-0"] = true
        await settle(host)
        #expect(model.mountedRows == ["activity-0", "activity-1"])
        #expect(host.fittingSize.height > foldedToolsHeight)
        model.toolGroupExpansions["tools:activity-0"] = false
        await settle(host)
        #expect(abs(host.fittingSize.height - foldedToolsHeight) < 1)
        model.isActive = false
        await settle(host)
        #expect(host.fittingSize.height < foldedToolsHeight)
        #expect(model.expansion == nil)
        model.expansion = true
        await settle(host)
        #expect(abs(host.fittingSize.height - foldedToolsHeight) < 1)
        model.expansion = false
        model.isActive = true
        await settle(host)
        #expect(host.fittingSize.height < foldedToolsHeight, "Live work cannot override a manual process collapse")
    }

    @Test("Tool group identity survives append and paging without crossing commentary or plan boundaries")
    func stableToolSegments() {
        let model = Model(expansion: nil)
        let commentary = AgentChatMessage(id: "progress", role: .assistant, text: "Public progress")
        let plan = AgentChatMessage(id: "plan", role: .operation, text: "A non-activity plan item")
        let messages = Array(model.messages.prefix(40)) + [commentary] + Array(model.messages.suffix(40)) + [plan]
        let segments = AgentChatProcessSegment.project(messages)
        #expect(segments.map(\.id) == ["tools:activity-0", "message:progress", "tools:activity-360", "message:plan"])
        #expect(segments.map(\.groupsActivities) == [true, false, true, false])
        let visible = AgentChatProcessWindow().indices(messages: messages, inspectedIDs: ["activity-0"])
        #expect(visible.contains(0) && visible.count == 33)
        #expect(segments[0].id == "tools:activity-0")
        let extended = AgentChatProcessSegment.project(Array(model.messages.prefix(40)) + [model.messages[40], commentary])
        #expect(extended.first?.id == segments.first?.id && extended.first?.messages.count == 41)
        #expect(AgentChatProcessSegment.project([model.messages[0]])[0].groupsActivities)
    }

    @Test("Hundreds of folded tools retain their preceding public progress")
    func longToolRunKeepsPublicContext() async {
        let model = Model(expansion: nil, status: .running)
        model.isActive = true
        model.messages.insert(.init(id: "context", role: .assistant, text: "Public progress explaining this tool run"), at: 0)
        let host = NSHostingView(rootView: Fixture(model: model))
        let window = window(host)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)
        #expect(model.mountedCommentary == ["context"])
        #expect(model.mountedRows.isEmpty)
        #expect(model.toolGroupExpansions.isEmpty && model.expansion == nil)
    }

    @Test("A second tool call preserves the first call's mounted details")
    func appendingToolPreservesInspection() async {
        let model = Model(expansion: nil)
        model.isActive = true
        let second = model.messages[1]
        model.messages = [model.messages[0]]
        model.toolGroupExpansions["tools:activity-0"] = true
        let host = NSHostingView(rootView: Fixture(model: model))
        let window = window(host)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)
        #expect(model.rowMountCounts == ["activity-0": 1])
        model.messages.append(second)
        await settle(host)
        #expect(model.rowMountCounts == ["activity-0": 1, "activity-1": 1])
        #expect(model.toolGroupExpansions == ["tools:activity-0": true])
        let inspectedHeight = host.fittingSize.height
        model.isActive = false
        await settle(host)
        #expect(abs(host.fittingSize.height - inspectedHeight) < 1, "Completion must retain manual tool inspection")
    }

    @Test(
        "New process outcomes remain collapsed until inspection",
        arguments: [AgentChatActivity.Status.running, .completed, .failed, .uncertain, .interrupted, .waitingForApproval, .waitingForInput])
    func outcomesDoNotOpenProcess(status: AgentChatActivity.Status) async throws {
        let model = Model(expansion: nil, status: status)
        let host = NSHostingView(rootView: Fixture(model: model))
        let window = window(host)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)
        #expect(model.parentMounted)
        #expect(model.mountedRows.isEmpty)
        #expect(AgentChatActivityIssueCounts(model.messages).failed == (status == .failed ? 400 : 0))
        #expect(AgentChatActivityIssueCounts(model.messages).uncertain == (status == .uncertain ? 400 : 0))
        model.expansion = true
        await settle(host)
        #expect(model.mountedRows.isEmpty, "Opening the public process must not mount a whole tool run")
        model.toolGroupExpansions["tools:activity-0"] = true
        await settle(host)
        #expect(model.mountedRows.count == AgentChatProcessWindow.pageSize)
    }

    @Test("Find temporarily reveals a manually collapsed process and restores that choice")
    func findRespectsManualCollapse() async throws {
        let model = Model(expansion: false)
        let host = NSHostingView(rootView: Fixture(model: model))
        let window = window(host)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)
        #expect(model.mountedRows.isEmpty)
        let collapsedHeight = host.fittingSize.height
        model.forceExpanded = true
        await settle(host)
        #expect(model.mountedRows.count == AgentChatProcessWindow.pageSize)
        let expandedHeight = host.fittingSize.height
        #expect(expandedHeight > collapsedHeight)
        model.forceExpanded = false
        await settle(host)
        #expect(model.expansion == false)
        #expect(abs(host.fittingSize.height - collapsedHeight) < 1)
        model.messages[399].activity?.status = .uncertain
        await settle(host)
        #expect(model.expansion == false)
        #expect(host.fittingSize.height < expandedHeight)
    }

    private func window(_ host: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return window
    }

    @Test("Conversation Find reveals retained activity without saving a disclosure choice")
    func conversationFindDoesNotPersistDisclosure() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/chat-activity-find/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let triptychID = UUID()
        var conversation = AgentChatConversation(triptychID: triptychID)
        conversation.title = "Synthetic activity inspection"
        conversation.messages = (0..<80).map { index in
            var message = AgentChatMessage(
                id: "operation-\(index)", role: .operation, text: "",
                activity: .init(
                    kind: .tool, status: .completed, source: .runtime,
                    subject: "Synthetic attachment", detail: index == 0 ? "Unique synthetic find target" : "Retained output"))
            message.turnID = "fixture-turn"
            return message
        }
        try await AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString)).save([conversation])
        let controller = fixtureChatController(triptychID: triptychID, root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try #require(await controller.waitUntilLoaded())
        let presentation = AgentChatDetailPresentation()
        let session = AgentChatReadingSession()
        let itemID = try #require(AgentChatTimelineProjection(conversation.messages).ids.first)
        let detail = AgentChatConversationDetailView(
            controller: controller, isVisible: true, addSelection: { _ in false },
            noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
            openAttachment: { _, _ in }, showChanges: { _ in }, showConversationChanges: { _ in },
            presentation: presentation, readingSession: session,
            nativeSession: AgentChatComposerSession(conversationID: conversation.id),
            focusRequest: nil, consumeFocusRequest: { _ in }, replyNavigation: .constant(nil), openReply: { _ in },
            showList: {}, newConversation: {}, didRestoreConversation: {}, renameConversation: { _ in }, showAccountUsage: {})
        let host = NSHostingView(rootView: detail)
        host.sizingOptions = []
        let window = window(host)
        defer {
            window.contentView = nil
            window.close()
        }
        try await wait(host) { session.markers[itemID]?.view != nil && session.isInitialTranscriptReady }
        let marker = try #require(session.markers[itemID]?.view)
        let initialHeight = marker.frame.height
        presentation.showsFind = true
        presentation.find.query = "Unique synthetic find target"
        presentation.find.refresh(messages: conversation.messages)
        try await wait(host) { presentation.find.selectedID == "operation-0" && marker.frame.height > initialHeight + 100 }
        #expect(session.expandedActivities.isEmpty)
        #expect(session.processExpansions.isEmpty)
        #expect(session.toolGroupExpansions.isEmpty)
        presentation.showsFind = false
        presentation.find = .init()
        try await wait(host) { abs(marker.frame.height - initialHeight) < 1 }
        #expect(session.expandedActivities.isEmpty)
        #expect(session.processExpansions.isEmpty)
        #expect(session.toolGroupExpansions.isEmpty)
        await controller.disconnect()
    }

    private func wait(_ host: NSView, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    private func settle(_ host: NSView) async {
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
    }

    @Test("Native default process layout reports mounted work without reading private data")
    func defaultProcessMeasurement() async throws {
        var samples: [Double] = []
        var rowCounts: [Int] = []
        for _ in 0..<7 {
            let model = Model(expansion: nil)
            let host = NSHostingView(rootView: Fixture(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            let start = ContinuousClock.now
            for _ in 0..<4 {
                host.layoutSubtreeIfNeeded()
                await Task.yield()
            }
            try #require(model.parentMounted)
            _ = host.fittingSize
            samples.append(milliseconds(start.duration(to: .now)))
            rowCounts.append(model.mountedRows.count)
            window.contentView = nil
            window.close()
        }
        #expect(rowCounts.allSatisfy { $0 <= AgentChatProcessWindow.pageSize })
        print("CHAT_ACTIVITY_BROWSING messages=400 samples_ms=\(samples) mounted_rows=\(rowCounts)")
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    @Test("Cold and retained tool-group toggles preserve bounded native rows and their selection")
    func toolGroupToggleMeasurement() async throws {
        let model = Model(expansion: true)
        let groupID = "tools:activity-0"
        model.toolGroupExpansions[groupID] = false
        let originalIDs = model.messages.map(\.id)
        let originalDetails = model.messages.map { Data(($0.activity?.detail ?? "").utf8) }
        let expectedRows = Set(model.messages.suffix(AgentChatProcessWindow.pageSize).map(\.id))
        let host = NSHostingView(rootView: Fixture(model: model))
        let window = window(host)
        defer {
            window.contentView = nil
            window.close()
        }
        let foldedHeight = try await stableNativeHeight(host) { _ in model.parentMounted && model.mountedRows.isEmpty }
        #expect(model.expansion == true && model.toolGroupExpansions[groupID] == false)

        let coldStart = ContinuousClock.now
        model.toolGroupExpansions[groupID] = true
        let expandedHeight = try await stableNativeHeight(host) { height in
            model.mountedRows == expectedRows && height > foldedHeight + 1
        }
        let coldMilliseconds = milliseconds(coldStart.duration(to: .now))
        let mountCounts = model.rowMountCounts
        let rowIdentities = try model.nativeRows.mapValues { ObjectIdentifier(try #require($0.view)) }
        #expect(model.mountedRows.count <= AgentChatProcessWindow.pageSize)
        #expect(mountCounts.values.allSatisfy { $0 == 1 })

        // This test-owned descendant probes native selection retention through
        // the production disclosure style. It does not measure Details text
        // selection, focus, clipboard delivery or visible paint. Attach it after
        // the cold sample so creating its TextKit session is outside that sample.
        let selectedRowID = try #require(expectedRows.sorted().first)
        let selectedRow = try #require(model.nativeRows[selectedRowID]?.view)
        let selectionEditor = NSTextView(frame: .zero)
        selectionEditor.string = "Synthetic native selection survives folding."
        selectionEditor.isEditable = false
        selectionEditor.isSelectable = true
        selectionEditor.isHidden = true
        selectedRow.addSubview(selectionEditor)
        let selection = NSRange(location: 10, length: 6)
        selectionEditor.setSelectedRange(selection)

        var warmOpenMilliseconds: [Double] = []
        var warmCloseMilliseconds: [Double] = []
        var mountedRowCounts: [Int] = []
        for index in 0..<8 {
            let opens = index % 2 == 1
            let start = ContinuousClock.now
            model.toolGroupExpansions[groupID] = opens
            let expectedHeight = opens ? expandedHeight : foldedHeight
            let height = try await stableNativeHeight(host) { height in
                abs(height - expectedHeight) < 1
            }
            let duration = milliseconds(start.duration(to: .now))
            if opens { warmOpenMilliseconds.append(duration) } else { warmCloseMilliseconds.append(duration) }
            mountedRowCounts.append(model.mountedRows.count)
            #expect(model.mountedRows == expectedRows && model.mountedRows.count <= AgentChatProcessWindow.pageSize)
            #expect(model.rowMountCounts == mountCounts, "Warm toggles must reuse the mounted native rows")
            let currentIdentities = try model.nativeRows.mapValues { ObjectIdentifier(try #require($0.view)) }
            #expect(currentIdentities == rowIdentities)
            #expect(selectionEditor.superview === selectedRow && selectionEditor.selectedRange() == selection)
            #expect(model.nativeRows[selectedRowID]?.view === selectedRow)
            #expect(model.expansion == true, "A tool-group toggle cannot replace its process disclosure choice")
            if !opens { #expect(abs(height - foldedHeight) < 1) }
        }
        #expect(model.messages.map(\.id) == originalIDs)
        #expect(model.messages.map { Data(($0.activity?.detail ?? "").utf8) } == originalDetails)
        #expect(warmOpenMilliseconds.count == 4 && warmCloseMilliseconds.count == 4)
        print(
            "CHAT_ACTIVITY_TOGGLE messages=400 cold_samples=1 cold_open_ms=\(coldMilliseconds) "
                + "warm_samples=8 warm_open_ms=\(warmOpenMilliseconds) warm_close_ms=\(warmCloseMilliseconds) "
                + "mounted_rows=\(mountedRowCounts) row_mount_counts=\(mountCounts.values.sorted()) "
                + "folded_height=\(foldedHeight) expanded_height=\(expandedHeight) "
                + "boundary=native_fixture_layout_and_main_actor_yields clock=elapsed "
                + "selection_probe=test_owned_native_descendant visible_paint_latency=unmeasured "
                + "window_never_ordered=true timing_threshold=none")
    }

    private func stableNativeHeight(_ host: NSView, until condition: (CGFloat) -> Bool) async throws -> CGFloat {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var previousHeight: CGFloat?
        var stablePasses = 0
        while ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            let height = host.fittingSize.height
            if height.isFinite, height > 0, condition(height) {
                stablePasses = previousHeight.map { abs($0 - height) < 0.5 } == true ? stablePasses + 1 : 1
                previousHeight = height
                if stablePasses == 3 { return height }
            } else {
                previousHeight = nil
                stablePasses = 0
            }
            await Task.yield()
        }
        try #require(stablePasses >= 3, "Synthetic tool-group native layout did not reach its expected stable height")
        return host.fittingSize.height
    }
}
