import AppKit
import SwiftUI

/// AppKit owns segment drawing, selection, focus and appearance adaptation.
struct InspectorLinkDirectionControl: NSViewRepresentable {
    @Binding var direction: ConnectionDirection
    var isActive = true

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> ScholiumTooltippedSegmentedControl {
        let control = ScholiumTooltippedSegmentedControl(frame: .zero)
        control.segmentCount = ConnectionDirection.allCases.count
        control.trackingMode = .selectOne
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectDirection(_:))
        control.segmentStyle = .roundRect
        control.borderShape = .capsule
        control.segmentDistribution = .fillEqually
        if #available(macOS 27.0, *) { control.role = .tabs }
        control.setAccessibilityLabel(ScholiumL10n.dynamicString("Links"))
        control.setAccessibilityIdentifier("scholium.links.direction")
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.isEnabled = isActive
        return control
    }

    func updateNSView(_ control: ScholiumTooltippedSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if !isActive, control.window?.firstResponder === control {
            control.window?.makeFirstResponder(nil)
        }
        control.isEnabled = isActive
        for (index, item) in ConnectionDirection.allCases.enumerated() {
            let title = ScholiumL10n.dynamicString(item.tabTitle)
            control.setLabel(item == direction ? title : "", forSegment: index)
            control.setImage(
                NSImage(systemSymbolName: item.symbol, accessibilityDescription: title), forSegment: index)
        }
        control.setSegmentToolTips(
            ConnectionDirection.allCases.map { ScholiumL10n.dynamicString($0.tabTitle) },
            isActive: isActive
        )
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
