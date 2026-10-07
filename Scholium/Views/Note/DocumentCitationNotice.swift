import SwiftUI

/// Citation feedback shares the Document notice owner across Review and Edit.
/// Actions stay with the document's existing mode and editor session owners.
struct DocumentCitationNotice: View {
    let presentation: DocumentCitationPresentation
    let dismiss: () -> Void
    let refresh: () -> Void
    let openSource: () -> Void

    var body: some View {
        if let status = presentation.status {
            ScholiumDocumentStatusNotice(
                ScholiumL10n.string("Citations"), detail: status, kind: .attention
            ) {
                Button("Dismiss", action: dismiss)
                    .scholiumActivationPointer()
            }
            .accessibilityIdentifier("scholium.document.citations.issue")
        }

        switch presentation.integrity {
        case .stale:
            ScholiumDocumentStatusNotice(
                ScholiumL10n.string("Citations need updating"),
                detail: ScholiumL10n.string("Refresh citations and bibliography in Zotero."),
                kind: .attention
            ) {
                Button("Refresh", action: refresh)
                    .disabled(!presentation.canRefresh)
                    .scholiumActivationPointer()
                sourceAction
            }
            .accessibilityIdentifier("scholium.document.citations.stale")
        case .unresolved:
            ScholiumDocumentStatusNotice(
                ScholiumL10n.string("Citation metadata needs repair"),
                detail: ScholiumL10n.string("Repair copied or damaged citation fields in Source. Your text is preserved."),
                kind: .attention
            ) {
                sourceAction
            }
            .accessibilityIdentifier("scholium.document.citations.unresolved")
        case nil:
            EmptyView()
        }
    }

    private var sourceAction: some View {
        Button("Source", action: openSource)
            .disabled(!presentation.canOpenSource)
            .scholiumActivationPointer()
    }
}
