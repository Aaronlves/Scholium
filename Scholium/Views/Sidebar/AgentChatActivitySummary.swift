import ScholiumContracts
import SwiftUI

/// The compact first-level activity label. Technical subjects remain in the
/// retained details; an exact Scholium Note may be opened directly here.
struct AgentChatActivitySummary: View {
    let activity: AgentChatActivity
    let noteTarget: AgentChatActivityNoteTarget?
    let openNote: (URL) -> Void
    @Environment(\.locale) private var locale

    private var title: String {
        AgentChatActivityProjection.title(activity, locale: locale)
    }

    private var showsStatus: Bool {
        activity.status != .running && activity.status != .completed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let noteTarget {
                HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    AgentChatActivityText(text: title)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        openNote(noteTarget.url)
                    } label: {
                        Text(verbatim: noteTarget.title)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .underline()
                            .scholiumContentControlInk(resting: .primaryText, emphasized: .accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.link)
                    .scholiumActivationPointer()
                    .scholiumContentControlPointerFeedback(
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius,
                            style: .continuous
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: ScholiumGrid.Dimension.preferredCustomTarget, alignment: .leading)
                    .help(Text("Open Note", bundle: .module))
                    .accessibilityLabel(
                        Text(verbatim: "\(ScholiumL10n.string("Open Note", locale: locale)): \(noteTarget.title)")
                    )
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    AgentChatActivityText(text: title)
                    if showsStatus {
                        Spacer(minLength: 4)
                        Text(activity.status.label(locale: locale)).foregroundStyle(.secondary)
                    }
                }
            }
            if noteTarget != nil, showsStatus {
                Text(activity.status.label(locale: locale)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
