import SwiftUI

enum DocumentSurfaceVisibility: Equatable {
    case active
    case retained

    var isActive: Bool {
        self == .active
    }
}

private struct ScholiumDocumentSurfaceVisibilityKey: EnvironmentKey {
    static let defaultValue = DocumentSurfaceVisibility.active
}

extension EnvironmentValues {
    var scholiumDocumentSurfaceVisibility: DocumentSurfaceVisibility {
        get { self[ScholiumDocumentSurfaceVisibilityKey.self] }
        set { self[ScholiumDocumentSurfaceVisibilityKey.self] = newValue }
    }
}
