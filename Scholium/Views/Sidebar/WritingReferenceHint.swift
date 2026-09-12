import SwiftUI

struct WritingReferenceHint: View {
    @AppStorage(ScholiumHotkeyPreferences.defaultsKey) private var hotkeys = ScholiumHotkeyPreferences.defaultData

    var body: some View {
        HStack {
            Text("Insert → Find Writing References…")
            if let binding = ScholiumHotkeyPreferences.binding(for: .findWritingReferences, data: hotkeys) {
                Text(binding.displayName)
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}
