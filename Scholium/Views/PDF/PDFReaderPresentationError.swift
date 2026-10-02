import Foundation
import ScholiumContracts

/// Contracts report typed failures; the frontend owns their interface language.
enum PDFReaderPresentationError {
    static func message(_ error: Error) -> String {
        if error is NoteInfoMetadataError {
            return ScholiumL10n.string("The authored pdf property must be one unambiguous string path. Open Source to edit it.")
        }
        guard let error = error as? PDFReaderError else { return error.localizedDescription }
        switch error {
        case .invalidBinding:
            return ScholiumL10n.string("The Note's pdf property does not identify a registered shared PDF.")
        case .missing:
            return ScholiumL10n.string("The shared PDF is missing. Choose an existing PDF or attach a new copy.")
        case .unreadable:
            return ScholiumL10n.string("Scholium cannot read this PDF. Check its permissions and availability.")
        case .malformed:
            return ScholiumL10n.string("The file is not a readable PDF.")
        case .locked:
            return ScholiumL10n.string("This PDF is encrypted or does not permit annotation. Use an unlocked copy.")
        case .tooLarge:
            return ScholiumL10n.string("This PDF exceeds the 512 MB reader limit.")
        case .changed:
            return ScholiumL10n.string("The PDF changed outside this reader. Your annotations remain available; reload or export them before continuing.")
        case .sourceChanged:
            return ScholiumL10n.string("The source PDF changed since it was imported. Import it as a new version to preserve the existing annotations.")
        case .destinationExists:
            return ScholiumL10n.string("A file already exists at the export destination. Choose a new filename.")
        case .unsafePath:
            return ScholiumL10n.string("The PDF path is linked, outside its registered folder, or no longer identifies the original file.")
        case .invalidState:
            return ScholiumL10n.string("The PDF reading position could not be saved.")
        case .saveUncertain(let location):
            return ScholiumL10n.string(
                "The PDF save could not be verified. Recovery copies are retained at \(location). Keep the reader open or export your annotations.")
        case .io(let message):
            return ScholiumL10n.string("The PDF could not be accessed: \(message)")
        }
    }
}
