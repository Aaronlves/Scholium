import SwiftUI

private struct DocumentToolbarUnderlapKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var documentToolbarUnderlap: Bool {
        get { self[DocumentToolbarUnderlapKey.self] }
        set { self[DocumentToolbarUnderlapKey.self] = newValue }
    }
}
