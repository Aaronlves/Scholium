import AppKit
import ScholiumContracts
import SwiftUI

/// Window state owns the destination. AppKit owns selection, keyboard focus,
/// sizing and appearance; this adapter only projects the three destinations.
struct ScholiumTriptychWorkspaceNavigator: NSViewRepresentable {
    let selectedSlot: WorkspaceVaultSlot?
    let noteCounts: SidebarWorkspaceNoteCounts
    let usesAccessibilitySize: Bool
    let select: (WorkspaceVaultSlot) -> Void
    @Environment(\.locale) private var locale

    func makeCoordinator() -> Coordinator { Coordinator(select: select) }

    func makeNSView(context: Context) -> WorkspaceSegmentedControl {
        let control = WorkspaceSegmentedControl()
        control.segmentCount = WorkspaceVaultSlot.allCases.count
        control.trackingMode = .selectOne
        control.segmentDistribution = .fillEqually
        control.segmentStyle = .roundRect
        control.borderShape = .capsule
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectWorkspace(_:))
        control.setAccessibilityIdentifier("scholium.workspaceNavigator")
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: WorkspaceSegmentedControl, context: Context) {
        context.coordinator.select = select
        control.controlSize = usesAccessibilitySize ? .large : .regular
        control.font = .systemFont(ofSize: NSFont.systemFontSize(for: control.controlSize))
        control.titles = WorkspaceVaultSlot.allCases.map {
            ScholiumL10n.dynamicString($0.displayName)
        }
        control.setAccessibilityLabel(ScholiumL10n.string("Triptych", locale: locale))
        for (index, slot) in WorkspaceVaultSlot.allCases.enumerated() {
            control.setEnabled(noteCounts.count(for: slot) != nil, forSegment: index)
            control.setToolTip(control.titles[index], forSegment: index)
        }
        control.selectedSegment =
            selectedSlot.flatMap {
                WorkspaceVaultSlot.allCases.firstIndex(of: $0)
            } ?? -1
        control.updateLabels()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WorkspaceSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: nsView.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var select: (WorkspaceVaultSlot) -> Void
        init(select: @escaping (WorkspaceVaultSlot) -> Void) { self.select = select }
        @objc func selectWorkspace(_ sender: NSSegmentedControl) {
            guard WorkspaceVaultSlot.allCases.indices.contains(sender.selectedSegment),
                sender.isEnabled(forSegment: sender.selectedSegment)
            else { return }
            select(WorkspaceVaultSlot.allCases[sender.selectedSegment])
        }
    }
}

@MainActor
final class WorkspaceSegmentedControl: NSSegmentedControl {
    var titles: [String] = []
    private(set) var usesSymbols = false
    private let symbols = ["doc.text.magnifyingglass", "point.3.connected.trianglepath.dotted", "square.and.pencil"]

    override func layout() {
        super.layout()
        updateLabels()
    }

    func updateLabels() {
        guard titles.count == segmentCount, segmentCount > 0 else { return }
        let font = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let requiredWidth =
            titles.map {
                ($0 as NSString).size(withAttributes: [.font: font]).width + 16
            }.max()! * CGFloat(segmentCount)
        usesSymbols = bounds.width > 0 && bounds.width < requiredWidth
        for index in titles.indices {
            let title = titles[index]
            let desiredLabel = usesSymbols ? "" : title
            if label(forSegment: index) != desiredLabel { setLabel(desiredLabel, forSegment: index) }
            if usesSymbols && image(forSegment: index) == nil {
                setImage(NSImage(systemSymbolName: symbols[index], accessibilityDescription: title), forSegment: index)
                setImageScaling(.scaleProportionallyDown, forSegment: index)
            } else if !usesSymbols && image(forSegment: index) != nil {
                setImage(nil, forSegment: index)
            }
        }
    }
}
