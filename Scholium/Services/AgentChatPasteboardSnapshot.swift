import AppKit
import ScholiumContracts
import UniformTypeIdentifiers

enum AgentChatTransferredMaterial: Sendable {
    case note(SidebarNoteDragItem)
    case file(URL)
    case image(Data)
}

/// Captures an explicit paste or drop; file references outrank icon images.
@MainActor enum AgentChatPasteboardSnapshot {
    static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .init(UTType.jpeg.identifier),
        .init(UTType.webP.identifier), .init(UTType.gif.identifier), .tiff,
    ]
    static var materialTypes: [NSPasteboard.PasteboardType] { [.init(SidebarNoteDragItem.pasteboardType), .fileURL] + imageTypes }
    static func read(_ pasteboard: NSPasteboard) -> [AgentChatTransferredMaterial] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            if let data = item.data(forType: .init(SidebarNoteDragItem.pasteboardType)) {
                guard let note = try? JSONDecoder().decode(SidebarNoteDragItem.self, from: data) else { return nil }
                return .note(note)
            }
            if let value = item.string(forType: .fileURL) {
                guard let url = URL(string: value), url.isFileURL else { return nil }
                return .file(url)
            }
            if let type = item.availableType(from: imageTypes), let data = item.data(forType: type) { return .image(data) }
            return nil
        }
    }

    static func resolve(_ item: SidebarNoteDragItem, in notes: [WorkspaceCatalogNote]) throws -> WorkspaceCatalogNote {
        let matches = notes.filter {
            $0.reference.vaultID == item.documentID.vaultID
                && $0.reference.stableNoteID.flatMap(UUID.init(uuidString:)) == item.stableNoteID
                && $0.reference.relativePath == item.documentID.relativePath
                && $0.fingerprint == item.revision
        }
        guard matches.count == 1, let note = matches.first else { throw AgentChatNoteMaterialError.changedSource }
        return note
    }
}
