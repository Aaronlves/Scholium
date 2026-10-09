import Combine
import Foundation
import ScholiumContracts

/// A preview keeps the release operation bound to the workspace that granted access.
@MainActor
struct DocumentAttachmentPreviewAccess {
    let lease: DocumentAttachmentPreviewLease
    let releaseAccess: (UUID) async -> Void

    func release() async { await releaseAccess(lease.accessToken) }
}

/// Only retains file access for SwiftUI's system Quick Look presentation.
/// The system owns the window, toolbar, opening actions and dismissal behavior.
@MainActor
final class DocumentAttachmentQuickLookSession: ObservableObject {
    @Published private(set) var url: URL?
    private var access: DocumentAttachmentPreviewAccess?
    private var preparation: Task<Void, Never>?
    private var preparationID: UUID?
    private var returnFocus: (() -> Void)?

    /// A new gesture owns preparation; stale results release their access
    /// without presenting after navigation, cancellation, or a newer gesture.
    func prepare(
        isCurrent: @escaping () -> Bool,
        acquire: @escaping () async throws -> DocumentAttachmentPreviewAccess,
        onFailure: @escaping (any Error) -> Void,
        returnFocus: @escaping () -> Void
    ) {
        dismiss(restoringFocus: false)
        let id = UUID()
        preparationID = id
        preparation = Task { [weak self] in
            do {
                let access = try await acquire()
                guard let self, self.preparationID == id else {
                    await access.release()
                    return
                }
                self.preparation = nil
                self.preparationID = nil
                guard !Task.isCancelled, isCurrent() else {
                    await access.release()
                    return
                }
                self.access = access
                self.returnFocus = returnFocus
                self.url = access.lease.fileURL
            } catch {
                guard let self, self.preparationID == id else { return }
                self.preparation = nil
                self.preparationID = nil
                if !Task.isCancelled, isCurrent() { onFailure(error) }
            }
        }
    }

    func dismiss(restoringFocus: Bool = true) {
        preparationID = nil
        preparation?.cancel()
        preparation = nil
        let restore = url == nil ? nil : returnFocus
        returnFocus = nil
        url = nil
        let access = self.access
        self.access = nil
        if let access { Task { await access.release() } }
        if restoringFocus { restore?() }
    }
}
