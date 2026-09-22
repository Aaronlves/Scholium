import Foundation

/// Shared, source-neutral file-link presentation for Review and Edit.
enum ScholiumAttachmentStyles {
    static let css = ScholiumDocumentWebResources.text(named: "attachments", extension: "css") ?? ""
}
