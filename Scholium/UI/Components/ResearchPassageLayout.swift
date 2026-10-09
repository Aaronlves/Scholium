import AppKit
import SwiftUI

/// Shared reading rail for source passages. The native List owns row grouping;
/// prose has no second card surface or control chrome.
struct ResearchPassageLayout<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @ScaledMetric(relativeTo: .body) private var pointSize = ScholiumTypography.controlPointSize

    var body: some View {
        content()
            .font(.system(size: pointSize))
            .lineSpacing(ScholiumGrid.Apparatus.passageLineSpacing)
            .padding(.leading, ScholiumGrid.Apparatus.passageLeadingInset)
            .padding(.trailing, ScholiumGrid.Apparatus.connectionOccurrenceVerticalInset)
            .padding(.vertical, ScholiumGrid.Apparatus.connectionOccurrenceVerticalInset)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Native text bounds resting previews at every width and text size. The full
/// readable source stays available through the separate context disclosure.
struct ResearchPassageExcerpt: View {
    let text: Text
    var isExpanded = false
    var lineLimit = 3

    var body: some View {
        ResearchText(text: text)
            .lineLimit(isExpanded ? nil : lineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The native text width determines the compact source window. Measurement
/// changes only the disposable excerpt, never the List's geometry or source.
struct ResearchPassagePreview: View {
    let source: String
    let matches: [Range<Int>]
    var lineLimit = 3
    let highlight: (ResearchCompactExcerpt) -> Text
    @State private var width: CGFloat = 180
    @ScaledMetric(relativeTo: .body) private var pointSize = ScholiumTypography.controlPointSize

    var body: some View {
        let excerpt = Self.fittingExcerpt(source: source, matches: matches, width: width, pointSize: pointSize, lineLimit: lineLimit)
        ResearchPassageExcerpt(text: highlight(excerpt), lineLimit: lineLimit)
            .font(.system(size: pointSize))
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
    }

    static func fittingExcerpt(source: String, matches: [Range<Int>], width: CGFloat, pointSize: CGFloat, lineLimit: Int = 3) -> ResearchCompactExcerpt {
        // Measure with the heavier match font to leave room for highlighted
        // words. Native text still owns wrapping and the final line bound.
        let font = NSFont.systemFont(ofSize: pointSize, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = ScholiumGrid.Apparatus.passageLineSpacing
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        let lineHeight = font.ascender - font.descender + font.leading
        let lines = CGFloat(max(1, lineLimit))
        let height = lineHeight * lines + paragraph.lineSpacing * (lines - 1)
        var budget = 180
        var excerpt = ResearchCompactExcerpt(text: source, matches: matches, characterLimit: budget)
        while budget > 12 {
            let measured = (excerpt.text as NSString).boundingRect(
                with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes
            )
            if measured.height <= height { break }
            budget -= 12
            excerpt = ResearchCompactExcerpt(text: source, matches: matches, characterLimit: budget)
        }
        return excerpt
    }
}

/// Inspector commands share label typography, ink and target geometry. Native
/// Button/Menu styles still own press, focus, disabled and menu feedback.
private struct ResearchInspectorActionLabel: ViewModifier {
    let iconOnly: Bool

    func body(content: Content) -> some View {
        content
            .font(ScholiumTypography.interface(.small))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
            .frame(
                minWidth: ScholiumGrid.Dimension.preferredCustomTarget,
                minHeight: ScholiumGrid.Dimension.preferredCustomTarget,
                alignment: iconOnly ? .center : .leading
            )
            .contentShape(Rectangle())
    }
}

extension View {
    func researchInspectorActionLabel(iconOnly: Bool = false) -> some View {
        modifier(ResearchInspectorActionLabel(iconOnly: iconOnly))
    }
}

struct ResearchPassageContextDisclosure: View {
    @Binding var expanded: Bool
    let identity: String
    let identifier: String

    var body: some View {
        Button {
            expanded.toggle()
        } label: {
            Text(expanded ? "Hide Context" : "Show Context")
                .researchInspectorActionLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: ScholiumL10n.string(expanded ? "Hide Context" : "Show Context") + ", " + identity))
        .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
        .accessibilityIdentifier("scholium.research.context." + identifier)
    }
}

/// Passage operations share one quiet control row below the source text. The
/// controls never capture writing context or own a source mutation themselves.
struct ResearchPassageControls<Actions: View>: View {
    @Binding var expanded: Bool
    let identity: String
    let identifier: String
    let isKept: Bool
    var canKeep = true
    let toggleKept: () -> Void
    @ViewBuilder let actions: () -> Actions
    private var keptActionTitle: LocalizedStringKey { isKept ? "Remove Kept Passage" : "Keep Passage" }

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ResearchPassageContextDisclosure(expanded: $expanded, identity: identity, identifier: identifier)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Button(action: toggleKept) {
                Label(keptActionTitle, systemImage: isKept ? "pin.fill" : "pin")
                    .labelStyle(.iconOnly)
                    .researchInspectorActionLabel(iconOnly: true)
            }
            .buttonStyle(.plain)
            .disabled(!canKeep)
            .help(keptActionTitle)
            .accessibilityLabel(Text(verbatim: ScholiumL10n.string(isKept ? "Remove Kept Passage" : "Keep Passage") + ", " + identity))
            .accessibilityValue(isKept ? Text("Kept snapshot") : Text(""))
            .accessibilityIdentifier("scholium.research.keep." + identifier)
            Menu(content: actions) {
                Label("Passage Actions", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .researchInspectorActionLabel(iconOnly: true)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help("Passage Actions")
            .accessibilityLabel(Text(verbatim: ScholiumL10n.string("Passage Actions") + ", " + identity))
            .accessibilityIdentifier("scholium.research.actions." + identifier)
        }
        .controlSize(.small)
        .padding(.leading, ScholiumGrid.Apparatus.passageLeadingInset)
    }
}
