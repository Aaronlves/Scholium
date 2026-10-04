import SwiftUI

/// Shared presentation for Library file tasks. The caller retains all operation
/// state and authority; this surface only arranges native controls and content.
struct FileOperationSheet<Content: View, Actions: View>: View {
    let title: Text
    let message: Text
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing) {
            VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.headerDetailSpacing) {
                title.font(.headline).accessibilityHeading(.h1)
                message.font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            HStack(spacing: ScholiumMetrics.ResearchSheet.footerControlSpacing) {
                actions
            }
        }
        .padding(ScholiumMetrics.ResearchSheet.contentInset)
        .frame(minWidth: ScholiumMetrics.ResearchSheet.FileOperation.minimumWidth)
        .presentationSizing(FileOperationSheetSizing())
        .background(ScholiumNativeColorRole.windowBackground.color)
        .tint(ScholiumNativeColorRole.controlAccent.color)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Fit short forms naturally, bounding long paths before measuring their height.
/// The presentation remains the sole owner of the sheet's content size.
private struct FileOperationSheetSizing: PresentationSizing {
    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        let width = min(root.sizeThatFits(.unspecified).width, ScholiumMetrics.ResearchSheet.FileOperation.maximumWidth)
        return ProposedViewSize(root.sizeThatFits(ProposedViewSize(width: width, height: nil)))
    }
}

struct FileOperationPath: View {
    let path: String
    var symbol = "doc.text"

    var body: some View {
        Label {
            Text(verbatim: path)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .font(.callout)
    }
}

/// Short lists fit on first layout; long lists keep a bounded native viewport.
struct FileOperationList<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: ScholiumMetrics.ResearchSheet.FileOperation.listMaximumHeight)
        .fixedSize(horizontal: false, vertical: true)
        .scrollBounceBehavior(.basedOnSize)
    }
}
