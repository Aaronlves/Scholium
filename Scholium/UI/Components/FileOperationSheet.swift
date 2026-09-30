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
        .frame(
            minWidth: ScholiumMetrics.ResearchSheet.FileOperation.minimumWidth,
            idealWidth: ScholiumMetrics.ResearchSheet.FileOperation.idealWidth
        )
        .presentationSizing(FileOperationSheetSizing())
        .background(ScholiumNativeColorRole.windowBackground.color)
        .tint(ScholiumNativeColorRole.controlAccent.color)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Refit at the established width when loading or wrapping changes the body.
/// The presentation remains the sole owner of the sheet's content size.
private struct FileOperationSheetSizing: PresentationSizing {
    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        let width = root.sizeThatFits(.unspecified).width
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

/// The measured content has an unconstrained vertical proposal. Only the native
/// scroll viewport is capped, so short lists fit and long paths remain readable.
struct FileOperationList<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat?

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    contentHeight = $0
                }
        }
        .frame(
            height: min(
                contentHeight ?? ScholiumMetrics.ResearchSheet.FileOperation.listMaximumHeight,
                ScholiumMetrics.ResearchSheet.FileOperation.listMaximumHeight)
        )
        .scrollBounceBehavior(.basedOnSize)
    }
}
