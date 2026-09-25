import AppKit
import Testing

@testable import ScholiumApp

@Suite("Segmented control tooltips")
@MainActor
struct SegmentedControlToolTipTests {
    @Test("Active segments register distinct Help regions and hidden panes remove them")
    func activeToolTipsFollowControlGeometry() {
        let control = ScholiumTooltippedSegmentedControl(
            frame: NSRect(x: 0, y: 0, width: 240, height: 28)
        )
        control.segmentCount = 3
        control.segmentDistribution = .fillEqually
        let messages = ["Incoming", "Outgoing", "External"]
        control.setSegmentToolTips(messages)

        let registrations = control.toolTipRegistrations
        #expect(registrations.count == 3)
        #expect(registrations.map(\.message) == messages)
        #expect(registrations.map(\.rect.width) == [80, 80, 80])
        #expect(registrations[0].rect.maxX == registrations[1].rect.minX)
        #expect(registrations[1].rect.maxX == registrations[2].rect.minX)
        for registration in registrations {
            #expect(
                control.view(
                    control,
                    stringForToolTip: registration.tag,
                    point: .zero,
                    userData: nil
                ) == registration.message
            )
        }

        control.setFrameSize(NSSize(width: 300, height: 28))
        #expect(control.toolTipRegistrations.map(\.rect.width) == [100, 100, 100])

        control.setSegmentToolTips(messages, isActive: false)
        #expect(control.toolTipRegistrations.isEmpty)
        #expect(
            control.view(
                control,
                stringForToolTip: registrations[0].tag,
                point: .zero,
                userData: nil
            ).isEmpty
        )
    }
}
