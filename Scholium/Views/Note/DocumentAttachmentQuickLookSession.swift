import Combine
import Foundation
import ScholiumContracts

/// Only retains file access for SwiftUI's system Quick Look presentation.
/// The system owns the window, toolbar, opening actions and dismissal behavior.
@MainActor
final class DocumentAttachmentQuickLookSession: ObservableObject {
    @Published private(set) var url: URL?
    private var lease: DocumentAttachmentPreviewLease?
    private var releaseAccess: ((UUID) async -> Void)?

    func present(_ lease: DocumentAttachmentPreviewLease, releaseAccess: @escaping (UUID) async -> Void) {
        dismiss()
        self.lease = lease
        self.releaseAccess = releaseAccess
        url = lease.fileURL
    }

    func dismiss() {
        url = nil
        let token = lease?.accessToken
        let release = releaseAccess
        lease = nil
        releaseAccess = nil
        if let token, let release { Task { await release(token) } }
    }
}
