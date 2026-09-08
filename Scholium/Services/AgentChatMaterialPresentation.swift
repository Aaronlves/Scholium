import Foundation
import ScholiumContracts

enum AgentChatLocalMaterialLabels {
  static func title(_ material: AgentChatLocalMaterial) -> String {
    switch material.source {
    case .file: material.fileName
    case .imageCapture(.clipboard): ScholiumL10n.string("Clipboard Image")
    case .imageCapture(.drop): ScholiumL10n.string("Dropped Image")
    }
  }
  static func error(_ error: Error) -> String {
    guard let failure = error as? AgentChatPDFPageSelectionFailure else { return error.localizedDescription }
    switch failure {
    case .invalidRange: return ScholiumL10n.string("Enter valid PDF page numbers, such as 1–5, 8.")
    case .tooManyPages: return ScholiumL10n.string("Choose up to 20 pages for one image input.")
    case .unavailable: return ScholiumL10n.string("The retained PDF is unavailable or locked. Replace it and try again.")
    }
  }

  static func pageRanges(_ pages: [Int]) -> String {
    var ranges: [ClosedRange<Int>] = []
    for page in pages {
      if let last = ranges.last, last.upperBound + 1 == page { ranges[ranges.count - 1] = last.lowerBound...page }
      else { ranges.append(page...page) }
    }
    return ranges.map { $0.lowerBound == $0.upperBound ? String($0.lowerBound) : "\($0.lowerBound)–\($0.upperBound)" }.joined(separator: ", ")
  }

  static func summary(_ material: AgentChatLocalMaterial) -> String {
    if let issue = material.issue {
      return switch issue {
      case .unreadable: ScholiumL10n.string("File could not be read")
      case .unsupported: ScholiumL10n.string("Unsupported file format")
      case .tooLarge: ScholiumL10n.string("File exceeds the input limit")
      case .locked: ScholiumL10n.string("PDF is locked")
      case .noText: ScholiumL10n.string("No text could be extracted")
      }
    }
    return switch material.kind {
    case .text: ScholiumL10n.string("Full Text Snapshot")
    case .pdf: material.pageImages.isEmpty ? ScholiumL10n.string("Extracted Text · \(material.pages.count) Pages")
      : ScholiumL10n.string("Page Images · \(material.pageImages.count) Pages")
    case .image: ScholiumL10n.string("Image Snapshot")
    case .unsupported: ScholiumL10n.string("Unsupported file format")
    }
  }
}
