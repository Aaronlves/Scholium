import AppKit

struct SegmentToolTipRegistration: Equatable {
    let tag: NSView.ToolTipTag
    let rect: NSRect
    let message: String
}

/// Uses AppKit's view-level tooltip rectangles because segmented-cell tooltip
/// values are stored but are not currently displayed by AppKit.
@MainActor
final class ScholiumTooltippedSegmentedControl: NSSegmentedControl, NSViewToolTipOwner {
    private(set) var segmentToolTipMessages: [String] = []
    private var segmentToolTipsAreActive = true
    private var installedBounds: NSRect?
    private var installedMessages: [String]?
    private var installedActiveState: Bool?
    private(set) var toolTipRegistrations: [SegmentToolTipRegistration] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { nil }

    func setSegmentToolTips(_ messages: [String], isActive: Bool = true) {
        segmentToolTipMessages = messages
        segmentToolTipsAreActive = isActive
        updateSegmentToolTips()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSegmentToolTips()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        updateSegmentToolTips()
    }

    override func layout() {
        super.layout()
        updateSegmentToolTips()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateSegmentToolTips()
    }

    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData: UnsafeMutableRawPointer?
    ) -> String {
        toolTipRegistrations.first { $0.tag == tag }?.message ?? ""
    }

    private func updateSegmentToolTips() {
        let bounds = self.bounds
        let isReady =
            segmentToolTipsAreActive
            && segmentDistribution == .fillEqually
            && segmentToolTipMessages.count == segmentCount
            && segmentCount > 0
            && bounds.width > 0
            && bounds.height > 0
        if installedBounds == bounds,
            installedMessages == segmentToolTipMessages,
            installedActiveState == isReady
        {
            return
        }

        removeAllToolTips()
        toolTipRegistrations.removeAll(keepingCapacity: true)
        installedBounds = bounds
        installedMessages = segmentToolTipMessages
        installedActiveState = isReady
        guard isReady else { return }

        let segmentWidth = bounds.width / CGFloat(segmentCount)
        for (index, message) in segmentToolTipMessages.enumerated() {
            let rect = NSRect(
                x: bounds.minX + CGFloat(index) * segmentWidth,
                y: bounds.minY,
                width: index == segmentCount - 1
                    ? bounds.maxX - (bounds.minX + CGFloat(index) * segmentWidth)
                    : segmentWidth,
                height: bounds.height
            )
            let tag = addToolTip(rect, owner: self, userData: nil)
            toolTipRegistrations.append(
                SegmentToolTipRegistration(tag: tag, rect: rect, message: message)
            )
        }
    }
}
