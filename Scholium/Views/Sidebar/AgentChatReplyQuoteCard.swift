import ScholiumContracts
import SwiftUI

struct AgentChatReplyQuoteCard: View {
    let quote: AgentChatReplyQuote
    var isEmbeddedInComposer = false
    let openOriginal: () -> Void
    var remove: (() -> Void)? = nil
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
                            .scholiumContentControlInk(
                                resting: .primaryText,
                                emphasized: .accent
                            )
                            .lineLimit(2).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .scholiumActivationPointer()
                .scholiumContentControlPointerFeedback(
                    in: RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    )
                )
                .accessibilityLabel(Text("Reply Excerpt"))
                .accessibilityValue(quote.text)
                if let remove {
                    Button(action: remove) {
                        ScholiumSidebarIcon(systemImage: ScholiumSidebarAction.remove.symbol, placement: .action)
                            .scholiumContentControlInk(
                                resting: .secondaryText,
                                emphasized: .primaryText
                            )
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
        .accessibilityIdentifier("scholium.chat.quote.\(quote.id)")
    }
}
