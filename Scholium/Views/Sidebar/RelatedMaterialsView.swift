import Combine
import ScholiumContracts
import SwiftUI

struct RelatedMaterialsView: View {
    @ObservedObject var session: RelatedMaterialsSession
    let isVisible: Bool
    let editor: MarkdownEditorSession?
    let find: @MainActor () -> Void
    let refresh: () -> Void
    let open: (RelatedMaterialCard) -> Void
    let addToChat: (RelatedMaterialCard) -> Void
    @State private var showsSelection = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ResearchInspectorLayout.sectionSpacing) {
                if let seed = session.seed {
                    Button {
                        showsSelection.toggle()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Based on Selected Text").font(.caption).foregroundStyle(.secondary)
                            Text(ResearchExcerptPresentation.readableText(seed.attachment.text))
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("scholium.related.selection")
                    .popover(isPresented: $showsSelection) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(URL(fileURLWithPath: seed.attachment.relativePath).deletingPathExtension().lastPathComponent)
                                    .font(.headline).help(seed.attachment.relativePath)
                                Text(ResearchExcerptPresentation.readableText(seed.attachment.text))
                                    .textSelection(.enabled)
                            }.padding()
                        }.frame(idealWidth: 360, maxHeight: 360)
                    }
                }
                if session.isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Finding related material").font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Cancel") { session.cancel() }
                    }
                }
                if let issue = session.issue {
                    Text(issue).foregroundStyle(.secondary).textSelection(.enabled)
                        .accessibilityIdentifier("scholium.related.issue")
                }
                if session.issue != nil, session.seed == nil {
                    Button("Retry", action: find).disabled(session.isLoading)
                }
                if session.needsRefresh || session.omittedCount > 0 {
                    Button("Refresh Results", action: refresh).disabled(session.isLoading)
                }
                if session.omittedCount > 0 {
                    Text("Some sources changed or could not be opened. Find again to refresh the results.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !session.isLoading, session.cards.isEmpty, session.issue == nil, session.omittedCount == 0 {
                    Text(
                        session.didSearch
                            ? String(localized: "No related material found in Analyses or Topics. Try another passage.", bundle: .module)
                            : String(localized: "Select text in Edit or Source. Related material appears here automatically.", bundle: .module)
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("scholium.related.empty")
                }
                ForEach(session.cards) { card in
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            open(card)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(card.candidate.title).font(.headline)
                                Text(highlightedExcerpt(card.passage)).font(.body).lineLimit(5)
                                    .multilineTextAlignment(.leading)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Open source: \(card.candidate.title)"))
                        .accessibilityHint(Text(card.passage.excerpt))
                        HStack {
                            Text(
                                card.reference.vaultRole == .sourceCorpus
                                    ? String(localized: "Analysis", bundle: .module)
                                    : String(localized: "Topic", bundle: .module)
                            )
                            .font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button("Add to Chat") { addToChat(card) }
                                .buttonStyle(.borderless)
                                .disabled(card.attachment == nil)
                                .help("Add the selected writing passage and this source to the current conversation.")
                                .accessibilityLabel(Text("Add to Chat: \(card.candidate.title)"))
                        }
                        Divider()
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
        .onAppear { if isVisible { session.scheduleSelectionSearch(immediate: true, find: find) } }
        .onChange(of: isVisible) { _, visible in
            if visible { session.scheduleSelectionSearch(immediate: true, find: find) } else { session.stopSelectionSearch() }
        }
        .onReceive(editor?.selectionChanges.eraseToAnyPublisher() ?? Empty<Bool, Never>().eraseToAnyPublisher()) { hasSelection in
            guard isVisible else { return }
            if !hasSelection || editor?.isComposing == true {
                session.stopSelectionSearch()
            } else {
                session.scheduleSelectionSearch(find: find)
            }
        }
        .onDisappear { session.stopSelectionSearch() }
    }

    private func highlightedExcerpt(_ passage: RelatedContentPassage) -> AttributedString {
        var result = AttributedString(passage.excerpt)
        for offsets in passage.excerptMatches {
            guard let range = Range(NSRange(location: offsets.lowerBound, length: offsets.count), in: passage.excerpt),
                let attributedRange = Range(range, in: result)
            else { continue }
            result[attributedRange].font = .body.bold()
        }
        return result
    }
}
