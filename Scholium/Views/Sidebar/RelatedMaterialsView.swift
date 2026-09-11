import ScholiumContracts
import SwiftUI

struct RelatedMaterialsView: View {
    @ObservedObject var session: RelatedMaterialsSession
    let find: () -> Void
    let refresh: () -> Void
    let open: (RelatedMaterialCard) -> Void
    let addToChat: (RelatedMaterialCard) -> Void
    @State private var showsSelection = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ResearchInspectorLayout.sectionSpacing) {
                HStack {
                    Button("Find from Selection", action: find)
                        .disabled(session.isLoading)
                        .accessibilityIdentifier("scholium.related.find")
                    Spacer(minLength: 0)
                    if session.isLoading {
                        ProgressView().controlSize(.small).accessibilityLabel("Finding related material")
                        Button("Cancel") { session.cancel() }
                    }
                }
                if let seed = session.seed {
                    DisclosureGroup(isExpanded: $showsSelection) {
                        Text(ResearchExcerptPresentation.readableText(seed.attachment.text)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Selected Passage").font(.subheadline)
                            Text(seed.attachment.relativePath).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("scholium.related.selection")
                }
                if let issue = session.issue {
                    Text(issue).foregroundStyle(.secondary).textSelection(.enabled)
                        .accessibilityIdentifier("scholium.related.issue")
                }
                if !session.isLoading, session.cards.isEmpty, session.issue == nil, session.omittedCount == 0 {
                    Text(
                        session.didSearch
                            ? String(localized: "No related material found in Analyses or Topics. Try another passage.", bundle: .module)
                            : String(localized: "Select a passage in Edit or Source to find related material.", bundle: .module)
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("scholium.related.empty")
                }
                if session.needsRefresh || session.omittedCount > 0 {
                    Button("Refresh Results", action: refresh).disabled(session.isLoading)
                }
                if session.omittedCount > 0 {
                    Text("Some sources changed or could not be opened. Find again to refresh the results.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(session.cards) { card in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(card.passage.displayText).font(.body).lineLimit(10).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.candidate.title).font(.subheadline)
                                Text(
                                    card.reference.vaultRole == .sourceCorpus
                                        ? String(localized: "Analysis", bundle: .module) : String(localized: "Topic", bundle: .module)
                                )
                                .font(.caption).foregroundStyle(.secondary)
                                Text(reason(card.passage.matches)).font(.caption).foregroundStyle(.secondary)
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack { actions(card) }
                                VStack(alignment: .leading) { actions(card) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("scholium.related.card.\(card.id)")
                }
                if !session.cards.isEmpty {
                    Text("These passages are retrieval leads, not assessments of support or disagreement.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, ResearchInspectorLayout.contentInset)
            .padding(.top, ResearchInspectorLayout.topInset)
            .padding(.bottom, ResearchInspectorLayout.bottomInset)
        }
        .accessibilityIdentifier("scholium.related")
    }

    @ViewBuilder private func actions(_ card: RelatedMaterialCard) -> some View {
        Button("Open Source") { open(card) }
            .accessibilityLabel(Text("Open source: \(card.candidate.title)"))
        Button("Add to Chat") { addToChat(card) }
            .disabled(card.attachment == nil)
            .help("Add the selected writing passage and this source to the current conversation.")
            .accessibilityLabel(Text("Add to Chat: \(card.candidate.title)"))
    }

    private func reason(_ matches: [RelatedContentSeedTermMatch]) -> String {
        switch matches.first?.seedKind {
        case .selectedPassage: String(localized: "Wording overlaps with the selected passage.", bundle: .module)
        case .researchRequest: String(localized: "Wording overlaps with your request.", bundle: .module)
        case .sourceNote, nil: String(localized: "Wording overlaps with the note's content.", bundle: .module)
        }
    }
}
