import Foundation
import ScholiumContracts
import SwiftUI

struct DocumentInformationDocumentID: Hashable, Sendable {
    let vaultID: UUID
    let relativePath: String
}

/// Window-local read-only projection for document chrome. The active editor or
/// reader remains the statistics owner; this model only lets the native
/// toolbar present that already-derived value without moving it into AppKit.
@MainActor
final class DocumentInformationProjection: ObservableObject {
    @Published private(set) var documentID: DocumentInformationDocumentID?
    @Published private(set) var statistics = DocumentStatistics.emptyBody
    @Published private(set) var headings: [HeadingNode] = []
    @Published private(set) var currentHeadingLine: Int?

    func activate(_ documentID: DocumentInformationDocumentID) {
        guard self.documentID != documentID else { return }
        self.documentID = documentID
        statistics = .emptyBody
        headings = []
        currentHeadingLine = nil
    }

    func publish(
        _ statistics: DocumentStatistics,
        for documentID: DocumentInformationDocumentID
    ) {
        guard self.documentID == documentID,
            self.statistics != statistics
        else { return }
        self.statistics = statistics
    }

    func clear(ifCurrent documentID: DocumentInformationDocumentID) {
        guard self.documentID == documentID else { return }
        self.documentID = nil
        statistics = .emptyBody
        headings = []
        currentHeadingLine = nil
    }

    func publishOutline(_ headings: [HeadingNode], currentLine: Int?, for documentID: DocumentInformationDocumentID) {
        guard self.documentID == documentID else { return }
        if self.headings != headings { self.headings = headings }
        if currentHeadingLine != currentLine { currentHeadingLine = currentLine }
    }

    func statistics(for documentID: DocumentInformationDocumentID) -> DocumentStatistics {
        self.documentID == documentID ? statistics : .emptyBody
    }
}

enum DocumentStatisticKind: String, CaseIterable, Identifiable {
    static let defaultsKey = "scholium.documentInformation.statisticKind"
    static let defaultValue = Self.words

    case words
    case charactersWithSpaces
    case charactersWithoutSpaces
    case hanCharacters

    var id: Self { self }

    var title: String {
        switch self {
        case .words: String(localized: "Words")
        case .charactersWithSpaces: String(localized: "Characters with Spaces")
        case .charactersWithoutSpaces: String(localized: "Characters without Spaces")
        case .hanCharacters: String(localized: "Han Characters")
        }
    }

    var compactTitle: String {
        switch self {
        case .words: String(localized: "Words")
        case .charactersWithSpaces, .charactersWithoutSpaces:
            String(localized: "Characters")
        case .hanCharacters: String(localized: "Han Characters")
        }
    }

    func value(in statistics: DocumentStatistics) -> Int {
        switch self {
        case .words: statistics.words
        case .charactersWithSpaces: statistics.charactersWithSpaces
        case .charactersWithoutSpaces: statistics.charactersWithoutSpaces
        case .hanCharacters: statistics.hanCharacters
        }
    }

    func label(in statistics: DocumentStatistics) -> String {
        let value = value(in: statistics).formatted(.number)
        return "\(value) \(title)"
    }

    func compactLabel(in statistics: DocumentStatistics) -> String {
        let value = value(in: statistics).formatted(.number)
        return "\(value) \(compactTitle)"
    }
}


struct DocumentOutlineSidebar: View {
    @ObservedObject var projection: DocumentInformationProjection
    let openHeading: (Int, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if projection.documentID == nil {
                Text("No Document Selected")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if projection.headings.isEmpty {
                    Text("No Headings")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.mutedText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    DocumentHeadingOutline(projection: projection, openHeading: openHeading)
                }
                Divider()
                DocumentStatisticPicker(statistics: projection.statistics)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ScholiumGrid.Spacing.nestedContentInset)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.outlineSidebar")
    }
}

private struct DocumentStatisticPicker: View {
    @AppStorage(DocumentStatisticKind.defaultsKey)
    private var selectedRaw = DocumentStatisticKind.defaultValue.rawValue
    let statistics: DocumentStatistics
    private var selected: DocumentStatisticKind { DocumentStatisticKind(rawValue: selectedRaw) ?? .words }

    var body: some View {
        Menu {
            ForEach(DocumentStatisticKind.allCases) { kind in
                Toggle(isOn: Binding(get: { selected == kind }, set: { if $0 { selectedRaw = kind.rawValue } })) {
                    Text(verbatim: kind.label(in: statistics))
                }
            }
        } label: {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                if statistics.scope == .selection { Text("Selection") }
                Text(verbatim: selected.compactLabel(in: statistics)).monospacedDigit()
            }
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.automatic)
        .tint(nil as Color?)
        .font(ScholiumTypography.interface(.small))
        .accessibilityIdentifier("scholium.documentStatisticPicker")
        .accessibilityLabel("Document Statistic")
        .accessibilityValue(Text(verbatim: selected.label(in: statistics)))
    }
}
