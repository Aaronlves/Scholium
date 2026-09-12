import ScholiumContracts
import SwiftUI

/// Shared identity, grid and native activation for both Inspector note groups.
struct ResearchNoteGroupHeader<Actions: View>: View {
    let title: String
    let role: VaultRole?
    @Binding var expanded: Bool
    var entranceProgress: CGFloat = 1
    @ViewBuilder let actions: () -> Actions
    @State private var hovered = false
    @FocusState private var keyboardFocused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsActions: Bool { hovered || keyboardFocused || accessibilityFocused }

    private var symbol: String {
        switch role {
        case .sourceCorpus: "doc.text.magnifyingglass"
        case .topicKnowledge: "point.3.connected.trianglepath.dotted"
        case .draftProject: "square.and.pencil"
        default: "doc.text"
        }
    }

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Button {
                expanded.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Apparatus.iconToTextGap) {
                    Image(systemName: symbol).frame(width: ScholiumGrid.Apparatus.iconColumnWidth)
                        .accessibilityHidden(true)
                    HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        Text(title).font(ScholiumTypography.interface(.control, emphasis: .strong))
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .opacity(showsActions ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
                    .researchGroupEntrance(entranceProgress)
            }
            .buttonStyle(.borderless)
            .focused($keyboardFocused)
            .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
            .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
            .help(role.map { ScholiumL10n.dynamicString($0.displayName) } ?? title)
            Menu(content: actions) {
                ScholiumSidebarHeaderIcon(systemImage: "ellipsis")
                    .opacity(showsActions ? 1 : 0)
                    .researchGroupEntrance(entranceProgress)
            }
            .scholiumSidebarHeaderControl()
            .focused($keyboardFocused)
            .accessibilityFocused($accessibilityFocused)
            .accessibilityLabel(Text("More Actions"))
            .help("More Actions")
        }
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: showsActions)
    }
}
