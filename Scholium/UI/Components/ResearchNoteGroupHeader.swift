import ScholiumContracts
import SwiftUI

/// Quiet role identity shared by result headers and captured-source attribution.
struct ResearchNoteRoleIcon: View {
    let role: VaultRole?

    private var symbol: String {
        switch role {
        case .sourceCorpus: "doc.text.magnifyingglass"
        case .topicKnowledge: "point.3.connected.trianglepath.dotted"
        case .draftProject: "square.and.pencil"
        default: "doc.text"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .frame(width: ScholiumGrid.Apparatus.iconColumnWidth)
            .accessibilityHidden(true)
    }
}

/// Shared identity, grid and native activation for both Inspector note groups.
struct ResearchNoteGroupHeader<Actions: View>: View {
    enum Count {
        case links(Int), passages(Int)

        var value: Int {
            switch self { case .links(let count), .passages(let count): count }
        }

        var label: String {
            switch self {
            case .links(let count):
                count == 1 ? ScholiumL10n.string("1 link") : ScholiumL10n.string("\(count) links")
            case .passages(let count):
                count == 1 ? ScholiumL10n.string("1 passage") : ScholiumL10n.string("\(count) passages")
            }
        }
    }

    let title: String
    let role: VaultRole?
    @Binding var expanded: Bool
    var count: Count? = nil
    var entranceProgress: CGFloat = 1
    var directoryContext: String? = nil
    var relativePath: String? = nil
    var separatesFromPreviousGroup = false
    @ViewBuilder let actions: () -> Actions
    private var sourceIdentity: String {
        ([title]
            + [
                count?.label,
                role.map { ScholiumL10n.dynamicString($0.displayName) }, relativePath,
            ].compactMap { $0 })
            .reduce("") { result, value in
                result.isEmpty ? value : ScholiumL10n.string("\(result), \(value)")
            }
    }

    var body: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Apparatus.iconToTextGap) {
                ResearchNoteRoleIcon(role: role)
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        ResearchText(text: Text(verbatim: title)).font(ScholiumTypography.interface(.control, emphasis: .strong))
                            .foregroundStyle(ScholiumNativeColorRole.label.color)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        if let count {
                            Text(count.value.formatted())
                                .font(ScholiumTypography.interface(.small))
                                .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                        }
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .accessibilityHidden(true)
                    }
                    if let directoryContext {
                        ResearchText(text: Text(verbatim: directoryContext))
                            .font(ScholiumTypography.interface(.small))
                            .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .frame(minHeight: ScholiumSidebarLayout.controlHeight)
            .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
            .researchGroupEntrance(entranceProgress)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: sourceIdentity))
        .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
        .help(sourceIdentity)
        .contextMenu(menuItems: actions)
        .padding(.top, separatesFromPreviousGroup ? ScholiumGrid.Apparatus.noteGroupSeparation : 0)
    }
}
