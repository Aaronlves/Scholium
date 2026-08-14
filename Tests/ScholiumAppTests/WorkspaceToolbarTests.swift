import AppKit
import Testing

@testable import ScholiumApp

@Suite("Workspace toolbar")
@MainActor
struct WorkspaceToolbarTests {
    @Test("The explicit Apparatus boundary does not invoke Inspector auto-discovery")
    func apparatusBoundaryHasOneGeometryOwner() {
        #expect(
            ScholiumWorkspaceToolbarController.Item.apparatusDivider
                != .inspectorTrackingSeparator
        )
    }
}
