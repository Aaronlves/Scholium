import ScholiumContracts
import SwiftUI

struct RecommendedBibliographySection: View {
    @ObservedObject var controller: RecommendedBibliographyController
    let openAnalysis: (VaultQualifiedNoteID) -> Void
    let openZoteroItem: (String) async -> Void
    let copyText: (String) -> Void
    let repairMethod: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            controls

            if !controller.visibleCandidates.isEmpty {
                VStack(spacing: 0) {
                    ForEach(controller.visibleCandidates) { candidate in
                        candidateRow(candidate)
                        if candidate.id != controller.visibleCandidates.last?.id {
                            Divider()
                        }
                    }
                }
                .background(
                    Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            } else if controller.target == nil {
                Text("Open an Analysis to prepare new recommendations for this Triptych.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if controller.projection?.state == .complete {
                Text("No warranted recommendations were returned for the inspected source scope.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if controller.phase == .ready {
                Text("No reading leads have been requested for this Analysis.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            status
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.recommendedBibliography")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label("Recommended Bibliography", systemImage: "text.book.closed")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 4)
            if !controller.visibleCandidates.isEmpty {
                Text(controller.visibleCandidates.count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "\(controller.visibleCandidates.count) recommendations"
                    )
            }
            Button {
                Task { await controller.retry() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh Recommended Bibliography")
            .accessibilityLabel("Refresh Recommended Bibliography")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(BibliographyRecommendationGoal.allCases, id: \.self) { goal in
                    Toggle(
                        goal.interfaceName,
                        isOn: Binding(
                            get: { controller.selectedGoals.contains(goal) },
                            set: { selected in
                                if selected {
                                    controller.selectedGoals.insert(goal)
                                } else {
                                    controller.selectedGoals.remove(goal)
                                }
                            }
                        )
                    )
                }
            } label: {
                Label(goalLabel, systemImage: "scope")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Recommendation goals")
            .accessibilityValue(goalLabel)
            .accessibilityIdentifier("scholium.recommendedBibliography.goals")

            TextField(
                "Purpose (optional)",
                text: $controller.purpose,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...3)
            .accessibilityHint(
                "Leave empty for neutral source-centered screening."
            )
            .accessibilityIdentifier("scholium.recommendedBibliography.purpose")

            HStack(spacing: 6) {
                Button(controller.projection == nil ? "Recommend…" : "Update Recommendations") {
                    controller.prepare()
                }
                .controlSize(.small)
                .disabled(!controller.canPrepare)
                .accessibilityIdentifier("scholium.recommendedBibliography.prepare")

                if let preparation = controller.preparation {
                    Button("Copy Instructions") {
                        copyText(preparation.instructions)
                    }
                    .controlSize(.small)
                    .accessibilityHint("Copy the immutable agent request packet.")
                    .accessibilityIdentifier("scholium.recommendedBibliography.copyInstructions")

                    Button("Cancel", role: .cancel) {
                        controller.cancel()
                    }
                    .controlSize(.small)
                    .disabled(controller.phase == .cancelling)
                    .accessibilityIdentifier("scholium.recommendedBibliography.cancel")
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch controller.phase {
        case .loading:
            ProgressView("Loading recommendations…")
                .controlSize(.small)
        case .preparing:
            ProgressView("Preparing request…")
                .controlSize(.small)
        case .awaitingAgent:
            Label("Awaiting agent completion", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("scholium.recommendedBibliography.awaitingAgent")
        case .cancelling:
            ProgressView("Cancelling…")
                .controlSize(.small)
        case .stale:
            Label(
                "Recommendations refer to an earlier Analysis revision.",
                systemImage: "clock.arrow.circlepath"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("scholium.recommendedBibliography.stale")
        case .cancelled:
            Label("Recommendation request cancelled", systemImage: "xmark.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("scholium.recommendedBibliography.cancelled")
        case .failed:
            if let error = controller.errorMessage {
                VStack(alignment: .leading, spacing: 5) {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry") { Task { await controller.retry() } }
                        .controlSize(.small)
                    if controller.needsMethodRepair {
                        Button("Repair in Research Guidance") { repairMethod() }
                            .controlSize(.small)
                            .accessibilityHint(
                                "Open Skills settings for the Recommended Bibliography method."
                            )
                    }
                }
            }
        case .idle, .ready:
            EmptyView()
        }
    }

    private func candidateRow(
        _ candidate: RecommendedBibliographyCandidate
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(candidate.identity.title ?? candidate.identity.rawCitation)
                .font(.caption.weight(.medium))
                .lineLimit(2)

            let identity = candidateIdentity(candidate)
            if !identity.isEmpty {
                Text(identity)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !candidate.goals.isEmpty {
                Text(candidate.goals.map(\.interfaceName).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(candidate.reason)
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)

            Label(candidate.matchState.interfaceName, systemImage: candidate.matchState.symbolName)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let analysis = candidate.matchedAnalysis {
                    Button("Open Analysis") { openAnalysis(analysis) }
                        .buttonStyle(.link)
                        .font(.caption2)
                }
                if let key = candidate.matchedZoteroItemKey {
                    Button("Open in Zotero") {
                        Task { await openZoteroItem(key) }
                    }
                    .buttonStyle(.link)
                    .font(.caption2)
                }
                Button("Dismiss") {
                    controller.dismiss(candidateID: candidate.id)
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(candidateAccessibilityLabel(candidate))
        .accessibilityIdentifier("scholium.recommendedBibliography.candidate.\(candidate.id.uuidString)")
    }

    private var goalLabel: String {
        controller.selectedGoals.isEmpty
            ? "Goals: Neutral"
            : "Goals: \(controller.selectedGoals.count)"
    }

    private func candidateIdentity(_ candidate: RecommendedBibliographyCandidate) -> String {
        let authors = candidate.identity.authors.joined(separator: ", ")
        return [authors.isEmpty ? nil : authors, candidate.identity.year.map(String.init)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func candidateAccessibilityLabel(
        _ candidate: RecommendedBibliographyCandidate
    ) -> String {
        [
            candidate.identity.title ?? candidate.identity.rawCitation,
            candidateIdentity(candidate),
            candidate.reason,
            candidate.matchState.interfaceName,
        ].filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

/// The Library's compact, scan-first projection. It deliberately keeps the
/// complete recommendation workflow in the existing popover rather than
/// squeezing forms and explanations into the navigation column.
struct SidebarRecommendedBibliographySection: View {
    @ObservedObject var controller: RecommendedBibliographyController
    let openAnalysis: (VaultQualifiedNoteID) -> Void
    let openZoteroItem: (String) async -> Void
    let copyText: (String) -> Void
    let repairMethod: () -> Void

    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("RECOMMENDED BIBLIOGRAPHY")
                    .font(ScholiumInterfaceTypography.editorialLabel)
                    .tracking(0.7)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text(controller.visibleCandidates.count.formatted())
                    .font(ScholiumInterfaceTypography.metadata.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityLabel(
                        "\(controller.visibleCandidates.count) bibliography recommendations"
                    )

                Button {
                    showsDetails = true
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .frame(
                            width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                            height: ScholiumMetrics.Accessibility.preferredCustomTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .layoutPriority(2)
                .help(
                    controller.target == nil
                        ? "Open an Analysis to prepare new recommendations; existing Triptych recommendations remain available"
                        : "Open Recommended Bibliography"
                )
                .accessibilityLabel("Open Recommended Bibliography")
                .accessibilityIdentifier("scholium.recommendedBibliography.open")
            }

            if controller.visibleCandidates.isEmpty {
                Text("None")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        ForEach(Array(controller.visibleCandidates.enumerated()), id: \.element.id) { index, candidate in
                            literatureEntry(candidate)
                            if index < controller.visibleCandidates.count - 1 {
                                ScholiumStructuralRule(orientation: .vertical)
                                    .frame(height: 28)
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .accessibilityLabel("Recommended literature")
            }
        }
        .popover(isPresented: $showsDetails, arrowEdge: .trailing) {
            ScrollView {
                RecommendedBibliographySection(
                    controller: controller,
                    openAnalysis: openAnalysis,
                    openZoteroItem: openZoteroItem,
                    copyText: copyText,
                    repairMethod: repairMethod
                )
                .padding(16)
            }
            .frame(width: 380, height: 520)
            .scholiumSurface(.boundedPanel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.recommendedBibliography.library")
    }

    private func literatureEntry(
        _ candidate: RecommendedBibliographyCandidate
    ) -> some View {
        let title = candidate.identity.title ?? candidate.identity.rawCitation
        return HStack(spacing: 0) {
            Text(literatureIdentity(candidate) + ", ")
            Text(title).italic()
        }
        .font(ScholiumInterfaceTypography.literatureCitation)
    }

    private func literatureIdentity(
        _ candidate: RecommendedBibliographyCandidate
    ) -> String {
        let authors = candidate.identity.authors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let authorText: String = switch authors.count {
        case 0: "Unknown author"
        case 1: authors[0]
        case 2: "\(authors[0]) & \(authors[1])"
        default: "\(authors[0]) et al."
        }
        return [authorText, candidate.identity.year.map(String.init)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private extension BibliographyRecommendationGoal {
    var interfaceName: String {
        switch self {
        case .backgroundReading: "Background Reading"
        case .corePositions: "Core Positions"
        case .historicalPredecessors: "Historical Predecessors"
        case .objections: "Objections"
        case .replies: "Replies"
        case .companionLiterature: "Companion Literature"
        case .alternativeApproaches: "Alternative Approaches"
        case .missingCitations: "Missing Citations"
        case .recentDevelopments: "Recent Developments"
        case .classicWorks: "Classic Works"
        }
    }
}

private extension BibliographyMatchState {
    var interfaceName: String {
        switch self {
        case .unmatched: "Unmatched reading lead"
        case .matchedZotero: "Matched in Zotero"
        case .matchedAnalysis: "Matching Analysis found"
        case .duplicate: "Probable duplicate reading lead"
        case .ambiguous: "Ambiguous match"
        }
    }

    var symbolName: String {
        switch self {
        case .unmatched: "book.closed"
        case .matchedZotero: "books.vertical"
        case .matchedAnalysis: "doc.text"
        case .duplicate: "doc.on.doc"
        case .ambiguous: "questionmark.diamond"
        }
    }
}
