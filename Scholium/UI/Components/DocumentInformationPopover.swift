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

    func activate(_ documentID: DocumentInformationDocumentID) {
        guard self.documentID != documentID else { return }
        self.documentID = documentID
        statistics = .emptyBody
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
    }

    func statistics(for documentID: DocumentInformationDocumentID) -> DocumentStatistics {
        self.documentID == documentID ? statistics : .emptyBody
    }
}

struct DocumentOutlineEntry: Hashable, Identifiable {
    let level: Int
    let text: String
    let sourceLine: Int

    var id: Int { sourceLine }
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

struct DocumentInformationPopoverView: View {
    @AppStorage(DocumentStatisticKind.defaultsKey)
    private var selectedStatisticRaw = DocumentStatisticKind.defaultValue.rawValue
    @ObservedObject var projection: DocumentInformationProjection
    let documentID: DocumentInformationDocumentID
    let headings: [DocumentOutlineEntry]
    let openHeading: (Int) -> Void

    private var statistics: DocumentStatistics {
        projection.statistics(for: documentID)
    }

    private var selectedStatistic: DocumentStatisticKind {
        DocumentStatisticKind(rawValue: selectedStatisticRaw)
            ?? DocumentStatisticKind.defaultValue
    }

    private func selectionBinding(for kind: DocumentStatisticKind) -> Binding<Bool> {
        Binding(
            get: { selectedStatistic == kind },
            set: { selected in
                guard selected else { return }
                selectedStatisticRaw = kind.rawValue
            }
        )
    }

    private var outlineHeight: CGFloat {
        guard !headings.isEmpty else {
            return ScholiumMetrics.DocumentInformation.emptyOutlineHeight
        }
        let contentHeight =
            CGFloat(headings.count)
            * ScholiumMetrics.DocumentInformation.outlineRowHeight
        return min(
            max(
                contentHeight,
                ScholiumMetrics.DocumentInformation.minimumOutlineHeight
            ),
            ScholiumMetrics.DocumentInformation.maximumOutlineHeight
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Text("Heading Outline")
                .font(ScholiumTypography.interface(.sectionTitle))

            Group {
                if headings.isEmpty {
                    Text("No Headings")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.mutedText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(headings) { heading in
                                Button {
                                    openHeading(heading.sourceLine)
                                } label: {
                                    Text(verbatim: heading.text)
                                        .font(ScholiumTypography.interface(.body))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(
                                            .leading,
                                            CGFloat(max(0, heading.level - 1))
                                                * ScholiumGrid.Spacing.nestedContentInset
                                        )
                                        .frame(
                                            minHeight: ScholiumMetrics.DocumentInformation
                                                .outlineRowHeight,
                                            alignment: .leading
                                        )
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .scholiumActivationPointer()
                                .accessibilityLabel(Text(verbatim: heading.text))
                                .accessibilityValue("Heading level \(heading.level)")
                            }
                        }
                    }
                }
            }
            .frame(height: outlineHeight)

            Divider()

            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Document Statistics")
                        .font(ScholiumTypography.interface(.sectionTitle))
                    if statistics.scope == .selection {
                        Spacer(minLength: ScholiumGrid.Spacing.nestedContentInset)
                        Text("Selection")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.mutedText)
                    }
                }

                Menu {
                    ForEach(DocumentStatisticKind.allCases) { kind in
                        Toggle(isOn: selectionBinding(for: kind)) {
                            Text(verbatim: kind.label(in: statistics))
                        }
                    }
                } label: {
                    Text(verbatim: selectedStatistic.compactLabel(in: statistics))
                        .lineLimit(1)
                        .monospacedDigit()
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(ScholiumTypography.interface(.small))
                .accessibilityIdentifier("scholium.documentStatisticPicker")
                .accessibilityLabel("Document Statistic")
                .accessibilityValue(Text(verbatim: selectedStatisticAccessibilityValue))
            }
        }
        .padding(ScholiumGrid.Spacing.sectionSeparation)
        .frame(
            maxWidth: ScholiumMetrics.DocumentInformation.maximumPopoverWidth,
            alignment: .leading
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private var selectedStatisticAccessibilityValue: String {
        let value = selectedStatistic.value(in: statistics)
        return "\(selectedStatistic.title), \(value)"
    }
}
