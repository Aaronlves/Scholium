import AppKit
import UniformTypeIdentifiers

enum AgentChatTransferredMaterial: Sendable {
  case file(URL)
  case image(Data)
}

/// Captures an explicit paste or drop; file references outrank icon images.
@MainActor enum AgentChatPasteboardSnapshot {
  static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .init(UTType.jpeg.identifier),
    .init(UTType.webP.identifier), .init(UTType.gif.identifier), .tiff]
  static var materialTypes: [NSPasteboard.PasteboardType] { [.fileURL] + imageTypes }
  static func read(_ pasteboard: NSPasteboard) -> [AgentChatTransferredMaterial] {
    (pasteboard.pasteboardItems ?? []).compactMap { item in
      if let value = item.string(forType: .fileURL) {
        guard let url = URL(string: value), url.isFileURL else { return nil }
        return .file(url)
      }
      if let type = item.availableType(from: imageTypes), let data = item.data(forType: type) { return .image(data) }
      return nil
    }
  }
}
