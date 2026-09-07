import Foundation
import ScholiumContracts
import Combine

struct DocumentInformationDocumentID: Hashable, Sendable {
    let vaultID: UUID
    let relativePath: String
}

/// Window-local read-only document projection. The active editor or reader
/// owns these derived values; no Inspector entry currently exposes them.
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
