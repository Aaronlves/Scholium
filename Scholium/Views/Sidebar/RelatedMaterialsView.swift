import Combine
import ScholiumContracts
import SwiftUI

struct RelatedMaterialsView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var session: RelatedMaterialsSession
    let isVisible: Bool
    let editor: MarkdownEditorSession?
    let termGroups: [SearchTermGroup]
    let find: @MainActor () -> Void
    let findWithTermGroup: @MainActor (SearchTermGroup?) -> Void
    let retry: () -> Void
    let open: (RelatedMaterialCard) -> Void
    let canAddToChat: Bool
    let addToChat: (RelatedMaterialCard) -> Void
    let insert: (RelatedMaterialCard) -> Void
    let insertParagraph: (RelatedMaterialCard) -> Void
    @State private var pointerInReferences = false
    @State private var entrance = ResearchGroupEntrance()
    @State private var hasMountedResults = false
    @Environment(\.scholiumReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: entrance.deadline == nil || reduceMotion)) { timeline in
            let groups = session.noteGroups
            List {
                Group {
                    if !termGroups.isEmpty || session.selectedTermGroup != nil {
                        Menu {
                            Picker(
                                "Find with term group",
                                selection: Binding(
                                    get: { session.selectedTermGroup?.id },
                                    set: { id in findWithTermGroup(termGroups.first { $0.id == id }) }
                                )
                            ) {
                                Text("No term group").tag(nil as UUID?)
                                ForEach(termGroups) { group in
                                    Text(group.name).tag(Optional(group.id))
                                }
                            }
                        } label: {
                            Label("Find with term group", systemImage: "text.magnifyingglass")
                        }
                        .accessibilityHint("Uses your authored search terms to find passages you can inspect before adding to Chat.")
                        .accessibilityIdentifier("scholium.related.termGroup")
                        .disabled(editor == nil || editor?.isComposing == true || session.isInsertingParagraphLink)
                        .researchListRow()
                    }
                    if let group = session.seed?.termGroup {
                        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                            Text("Term group: \(group.name)").font(.caption.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Original terms: \(group.terms.joined(separator: ", "))").font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            Text(
                                verbatim:
                                    ScholiumL10n.string("Term group: \(group.name)", locale: locale) + ". "
                                    + ScholiumL10n.string("Original terms: \(group.terms.joined(separator: ", "))", locale: locale))
                        )
                        .accessibilityIdentifier("scholium.related.termGroupProvenance")
                        .researchListRow()
                    }
                    switch session.presentation {
                    case .waiting:
                        ScholiumSidebarState(
                            Text("Writing References"),
                            detail: Text("Pause writing or select a passage."),
                            indicator: .symbol("text.magnifyingglass"), horizontalInset: 0
                        ) {
                            WritingReferenceHint()
                        }
                    case .empty:
                        ScholiumSidebarState(
                            Text("No related material"), indicator: .symbol("magnifyingglass"), horizontalInset: 0
                        )
                        .accessibilityIdentifier("scholium.related.empty")
                    case .problem(let message):
                        ScholiumSidebarState(
                            Text("References unavailable"), detail: Text(message),
                            indicator: .symbol("exclamationmark.triangle", role: .attention), horizontalInset: 0
                        ) {
                            Button("Retry", action: retry).disabled(editor == nil)
                        }
                        .accessibilityIdentifier("scholium.related.issue")
                    case .loading:
                        if session.cards.isEmpty {
                            ForEach(0..<3) { index in
                                RelatedMaterialSkeleton(separatesFromPreviousGroup: index > 0)
                            }
                        }
                    case .results:
                        EmptyView()
                    }
                    ForEach(groups) { group in
                        RelatedMaterialNoteGroupView(
                            group: group,
                            termGroup: session.seed?.termGroup,
                            canInsert: editor != nil && session.insertionPoint != nil && !session.isLoading && !session.isInsertingParagraphLink,
                            canInsertParagraph: editor != nil && session.canInsertParagraphLink,
                            canAddToChat: canAddToChat,
                            isLoading: session.isLoading,
                            entranceProgress: reduceMotion
                                ? 1 : entrance.progress(for: group.id, at: timeline.date),
                            separatesFromPreviousGroup: group.id != groups.first?.id,
                            open: { if !session.isLoading { open($0) } },
                            insert: { if !session.isLoading { insert($0) } },
                            insertParagraph: insertParagraph,
                            addToChat: { if !session.isLoading { addToChat($0) } }
                        )
                        .redacted(reason: session.isLoading ? .placeholder : [])
                        .modifier(ResearchSkeletonPulse(isActive: session.isLoading))
                        .disabled(session.isLoading)
                        .allowsHitTesting(!session.isLoading)
                    }

                }
                .researchListRow()
            }
            .researchListStyle()
        }
        .accessibilityIdentifier("scholium.related")
        .accessibilityValue(session.isLoading ? Text("Finding related material") : Text(""))
        .help("These passages are retrieval leads, not assessments of support or disagreement.")
        .onAppear {
            if !session.isLoading { scheduleFollowing(immediate: true) }
        }
        .onChange(of: session.noteGroups.map(\.id), initial: true) { _, ids in
            if hasMountedResults {
                entrance.update(ids, at: .now, reduceMotion: reduceMotion)
            } else {
                entrance.showExisting(ids)
                hasMountedResults = true
            }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { entrance.finish() }
        }
        .task(id: entrance.deadline) {
            guard let deadline = entrance.deadline else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                try Task.checkCancellation()
                entrance.finish()
            } catch {}
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                if !session.isLoading { scheduleFollowing(immediate: true) }
            } else {
                session.stopAutomaticSearch()
            }
        }
        .onChange(of: editor.map(ObjectIdentifier.init)) { _, _ in
            pointerInReferences = false
            scheduleFollowing(immediate: true)
        }
        .onHover { inside in
            pointerInReferences = inside
            if inside { session.stopAutomaticSearch() } else { scheduleFollowing() }
        }
        .onReceive(
            editor?.writingContextChanges.eraseToAnyPublisher()
                ?? Empty<Void, Never>().eraseToAnyPublisher()
        ) { _ in
            session.invalidateWritingContext()
            // Writing resumes following even when the pointer was left over the sidebar.
            if editor?.hasWritingFocus == true { pointerInReferences = false }
            scheduleFollowing()
        }
        .onDisappear { session.stopAutomaticSearch() }
    }

    private func scheduleFollowing(immediate: Bool = false) {
        guard isVisible, immediate || !pointerInReferences, let editor, !editor.isComposing else {
            session.stopAutomaticSearch()
            return
        }
        session.scheduleAutomaticSearch(
            selection: editor.hasNonemptySelection, immediate: immediate, find: find)
    }

}
