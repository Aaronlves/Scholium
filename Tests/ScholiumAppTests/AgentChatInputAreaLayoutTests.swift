import AppKit
import ScholiumContracts
import SwiftUI
import Synchronization
import Testing

@testable import ScholiumApp

@Suite("Chat input-area viewport allocation", .serialized)
@MainActor
struct AgentChatInputAreaLayoutTests {
    @Test("A short viewport retains a reading passage and scrolls prepared input within the remaining area")
    func shortViewportAllocation() throws {
        let height: CGFloat = 420
        let limits = AgentChatInputAreaLimits.fitting(
            viewportHeight: height, hasQueue: true, hasPreparedContent: true,
            lineHeight: 20)
        let maximum = try #require(limits.maximumHeight)
        let reading = try #require(limits.reservedTranscriptHeight)
        let queue = try #require(limits.queueMaximumHeight)
        let preparation = try #require(limits.preparationMaximumHeight)
        let editor = try #require(limits.editorMaximumHeight)
        #expect(reading >= 6 * 20)
        #expect(maximum + reading == height)
        #expect(queue >= ScholiumGrid.Dimension.preferredCustomTarget && queue < 144)
        #expect(preparation >= ScholiumGrid.Dimension.preferredCustomTarget)
        #expect(editor >= 40 && editor < 7 * 20 + 12)
        // The remaining height includes input/queue control rows and all of
        // their existing outer padding; none is removed to meet the budget.
        #expect(queue + preparation + editor < maximum)
    }

    @Test("An ordinary tall viewport keeps existing request and queue limits rather than expanding those surfaces")
    func tallViewportPreservesLocalCaps() throws {
        let limits = AgentChatInputAreaLimits.fitting(
            viewportHeight: 1_400, hasQueue: true, hasPreparedContent: false,
            lineHeight: 20)
        #expect(limits.queueMaximumHeight == 144)
        #expect(limits.requestMaximumHeight == 240)
        let editorMaximum = try #require(limits.editorMaximumHeight)
        let sevenLineMaximum: CGFloat = 7 * 20 + 12
        #expect(editorMaximum == sevenLineMaximum)
        #expect(limits.preparationMaximumHeight == nil)
        let unmounted = AgentChatInputAreaLimits.fitting(
            viewportHeight: nil, hasQueue: true, hasPreparedContent: true,
            lineHeight: 20)
        #expect(unmounted == .unconstrained)
    }

    private struct ControlProbe: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.identifier = .init("request-control")
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {}
    }

    @Test("A request-body budget preserves its separate native decision controls")
    func requestBodyScrollsAboveControls() throws {
        _ = NSApplication.shared
        let host = NSHostingView(
            rootView: VStack(spacing: 12) {
                AgentChatContentScroll {
                    Text(String(repeating: "Exact permission scope 保留完整权限说明。\n", count: 30))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Allow Once") {}
                    .frame(minHeight: ScholiumGrid.Dimension.preferredCustomTarget)
                    .background(ControlProbe())
            }
            .environment(\.agentChatContentMaximumHeight, 80)
            .frame(width: 300))
        // Keep the tested native viewport stable. Preferred-content sizing can
        // shrink its host after layout, leaving probes in the previous frame.
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 180)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let control = try #require(descendants(host).first { $0.identifier?.rawValue == "request-control" })
        #expect(control.bounds.height >= ScholiumGrid.Dimension.preferredCustomTarget)
        #expect(host.fittingSize.height <= 80 + 12 + ScholiumGrid.Dimension.preferredCustomTarget + 1)
        let frame = control.convert(control.bounds, to: host)
        #expect(host.bounds.contains(frame))
    }

    @Test("Long tool-request context shares the question-body budget at narrow and ordinary widths", arguments: [220.0, 320.0])
    func toolRequestContextSharesBodyBudget(width: Double) async throws {
        _ = NSApplication.shared
        let bodyBudget: CGFloat = 80
        let measurement = QuestionFormMeasurement()
        let question = AgentChatQuestion(
            id: "synthetic-tool-question", prompt: "Describe the requested source range.",
            options: [], allowsOther: true, isSecret: false)
        let host = NSHostingView(
            rootView: MeasuredQuestionForm(measurement: measurement) {
                AgentChatQuestionForm(
                    questions: [question], answers: .constant([question.id: .text("Keep this answer")]),
                    isSubmitting: false, failure: nil,
                    toolContext: String(repeating: "Synthetic tool context 保留完整请求说明。\n", count: 30),
                    technicalDetail: "Synthetic inspectable arguments", reply: {}, skip: {}
                )
                .environment(\.agentChatContentMaximumHeight, bodyBudget)
            }
            .frame(width: CGFloat(width)))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: 180)
        // This window supplies native layout without ordering, activation or
        // foreground QA. The real form, including its decision row, is measured.
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        for _ in 0..<5 {
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        let size = try #require(measurement.size.withLock { $0 })
        #expect(size.width.isFinite && size.height.isFinite && size.width > 0)
        #expect(abs(size.width - CGFloat(width)) < 0.5, "Measure the form at the requested viewport width")
        #expect(size.height > bodyBudget, "The complete form includes its separate decision row")
        #expect(!window.isVisible)
        #expect(
            size.height
                <= bodyBudget + ScholiumGrid.Spacing.nestedContentInset + ScholiumMetrics.AgentChat.composerPrimaryControlTarget + 1,
            "Tool context must scroll with the question rather than displace the separate decision row")
    }
}

/// Measure the real form with the width-only proposal used by its input-area
/// owner. NSHostingView's minimum fittingSize may compress multiline context.
private final class QuestionFormMeasurement: Sendable {
    let size = Mutex<CGSize?>(nil)
}

private struct MeasuredQuestionForm: Layout {
    let measurement: QuestionFormMeasurement

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(.init(width: proposal.width, height: nil)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let form = subviews.first else { return }
        let formProposal = ProposedViewSize(width: bounds.width, height: nil)
        let size = form.sizeThatFits(formProposal)
        measurement.size.withLock { $0 = size }
        form.place(at: bounds.origin, anchor: .topLeading, proposal: formProposal)
    }
}
