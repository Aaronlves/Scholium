import ScholiumContracts
import SwiftUI

struct AgentChatReplyQuoteCard: View {
    let quote: AgentChatReplyQuote
    var isEmbeddedInComposer = false
    let openOriginal: () -> Void
    var remove: (() -> Void)? = nil
    @Environment(\.scholiumDocumentSurfaceVisibility) private var surfaceVisibility
    @State private var showsPreview = false

    var body: some View {
        AgentChatMaterialContainer(isEmbeddedInComposer: isEmbeddedInComposer) {
            HStack(alignment: .top, spacing: 6) {
                Button {
                    showsPreview = true
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "quote.opening").foregroundStyle(.secondary)
                        Text(verbatim: quote.text)
                            .lineLimit(2).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(ScholiumContentActionButtonStyle(restingRole: .primaryText))
                .accessibilityLabel(Text("Reply Excerpt"))
                .accessibilityValue(quote.text)
                if let remove {
                    Button(action: remove) {
                        ScholiumSidebarIcon(systemImage: ScholiumSidebarAction.remove.symbol, placement: .action)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(ScholiumContentActionButtonStyle())
                    .accessibilityLabel("Remove Quote")
                }
            }
        }
        .frame(width: 210).fixedSize(horizontal: false, vertical: true)
        .popover(isPresented: $showsPreview) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Reply Excerpt").font(.headline)
                    Spacer()
                    Button("Close") { showsPreview = false }.keyboardShortcut(.cancelAction)
                }
                ScrollView { Text(verbatim: quote.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 260)
                Button("Original Reply") {
                    showsPreview = false
                    openOriginal()
                }
            }.padding().frame(width: 320).tint(nil as Color?)
        }
        .onChange(of: surfaceVisibility) { _, visibility in
            if !visibility.isActive { showsPreview = false }
        }
        .onDisappear { showsPreview = false }
        .accessibilityIdentifier("scholium.chat.quote.\(quote.id)")
    }
}
