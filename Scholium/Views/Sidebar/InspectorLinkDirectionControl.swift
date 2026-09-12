import AppKit
import SwiftUI

/// AppKit owns segment drawing, selection, focus and appearance adaptation.
struct InspectorLinkDirectionControl: NSViewRepresentable {
    @Binding var direction: ConnectionDirection

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: ConnectionDirection.allCases.map { _ in "" },
            trackingMode: .selectOne, target: context.coordinator,
            action: #selector(Coordinator.selectDirection(_:)))
        control.segmentStyle = .roundRect
        control.borderShape = .capsule
        control.segmentDistribution = .fill
        if #available(macOS 27.0, *) { control.role = .tabs }
        control.setAccessibilityLabel(ScholiumL10n.dynamicString("Links"))
        control.setAccessibilityIdentifier("scholium.links.direction")
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        for (index, item) in ConnectionDirection.allCases.enumerated() {
            let title = ScholiumL10n.dynamicString(item.tabTitle)
            control.setLabel(item == direction ? title : "", forSegment: index)
            control.setImage(
                NSImage(systemSymbolName: item.symbol, accessibilityDescription: title), forSegment: index)
            control.setToolTip(title, forSegment: index)
        }
        control.selectedSegment = ConnectionDirection.allCases.firstIndex(of: direction) ?? 0
        control.invalidateIntrinsicContentSize()
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
            guard ConnectionDirection.allCases.indices.contains(control.selectedSegment) else { return }
            parent.direction = ConnectionDirection.allCases[control.selectedSegment]
        }
    }
}
