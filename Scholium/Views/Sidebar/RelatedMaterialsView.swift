import Combine
import ScholiumContracts
import SwiftUI

struct RelatedMaterialsView: View {
    @ObservedObject var session: RelatedMaterialsSession
    let isVisible: Bool
    let editor: MarkdownEditorSession?
    let find: @MainActor () -> Void
    let retry: () -> Void
    let open: (RelatedMaterialCard) -> Void
    let addToChat: (RelatedMaterialCard) -> Void
    let insert: (RelatedMaterialCard) -> Void
    @State private var pointerInReferences = false
    @State private var entrance = ResearchGroupEntrance()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: entrance.deadline == nil || reduceMotion)) { timeline in
            List {
                Group {
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
                        ForEach(0..<3) { _ in RelatedMaterialSkeleton() }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("Finding related material"))
                    case .results:
                        EmptyView()
                    }
                    ForEach(session.noteGroups) { group in
                        RelatedMaterialNoteGroupView(
                            group: group,
                            canInsert: editor != nil && session.insertionPoint != nil && !session.isLoading,
                            entranceProgress: reduceMotion ? 1 : entrance.progress(for: group.id, at: timeline.date),
                            open: open, insert: insert, addToChat: addToChat)
                    }

                }
                .researchListRow()
            }
            .researchListStyle()
        }
        .accessibilityIdentifier("scholium.related")
        .help("These passages are retrieval leads, not assessments of support or disagreement.")
        .onAppear {
            if !session.isLoading { scheduleFollowing(immediate: true) }
        }
        .onChange(of: session.noteGroups.map(\.id), initial: true) { _, ids in
            entrance.update(ids, at: .now, reduceMotion: reduceMotion)
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
