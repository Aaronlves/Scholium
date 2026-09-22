import SwiftUI

/// A stable text treatment. Execution identity and state stay with the caller;
/// the disclosure indicator carries any optional activity motion.
struct AgentChatActivityText: View {
    let text: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(verbatim: text)
            .foregroundStyle(contrast == .increased ? .primary : .secondary)
    }
}
