import SwiftUI

struct WritingReferenceHint: View {
    @AppStorage(ScholiumHotkeyPreferences.defaultsKey) private var hotkeys = ScholiumHotkeyPreferences.defaultData

    var body: some View {
        HStack {
            Text("Research → Find Related Material for Writing")
            if let binding = ScholiumHotkeyPreferences.binding(for: .findWritingReferences, data: hotkeys) {
                Text(binding.displayName)
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}
