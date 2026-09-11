import AppKit
import SwiftUI

/// AppKit owns segment drawing, selection, focus and appearance adaptation.
struct InspectorLinkDirectionControl: NSViewRepresentable {
    @Binding var direction: ConnectionDirection

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: [ScholiumL10n.dynamicString("Incoming"), ScholiumL10n.dynamicString("Outgoing")],
            trackingMode: .selectOne, target: context.coordinator,
            action: #selector(Coordinator.selectDirection(_:)))
        control.segmentStyle = .roundRect
        control.borderShape = .capsule
        control.segmentDistribution = .fillEqually
        control.setAccessibilityLabel(ScholiumL10n.dynamicString("Link Direction"))
        control.setAccessibilityIdentifier("scholium.links.direction")
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = direction == .incoming ? 0 : 1
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: NSSegmentedControl,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.intrinsicContentSize.width,
            height: nsView.intrinsicContentSize.height)
    }

    @MainActor final class Coordinator: NSObject {
        var parent: InspectorLinkDirectionControl
        init(parent: InspectorLinkDirectionControl) { self.parent = parent }
        @objc func selectDirection(_ control: NSSegmentedControl) {
            parent.direction = control.selectedSegment == 0 ? .incoming : .outgoing
        }
    }
}
