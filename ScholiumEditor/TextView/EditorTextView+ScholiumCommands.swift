import AppKit

extension EditorTextView {
    public enum DocumentCommandError: Error, LocalizedError {
        case unavailable, invalidRange, invalidArgument
        case unsupported(String)
        case rejected(String)
        public var errorDescription: String? {
            switch self {
            case .unavailable: "The document is not currently editable."
            case .invalidRange: "The command range does not belong to the current document."
            case .invalidArgument: "The document command has an invalid argument."
            case .unsupported(let command): "The document command is unavailable: \(command)."
            case .rejected(let message): message
            }
        }
    }

    public struct DocumentTablePosition: Sendable {
        public let row: Int
        public let column: Int
        public let rowCount: Int
        public let columnCount: Int
        public let canDeleteRow: Bool
        public let canDeleteColumn: Bool
    }

    public var documentTablePosition: DocumentTablePosition? {
        guard let cell = tableCell(atRawOffset: selectedRange().location),
            let lines = tableLines(blockIndex: cell.blockIndex)
        else { return nil }
        return DocumentTablePosition(
            row: cell.row == 0 ? 0 : cell.row - 1,
            column: cell.column, rowCount: lines.count - 1,
            columnCount: tableColumnCount(blockIndex: cell.blockIndex),
            canDeleteRow: canDeleteTableRow(blockIndex: cell.blockIndex, row: cell.row),
            canDeleteColumn: canDeleteTableColumn(blockIndex: cell.blockIndex, column: cell.column))
    }

    public var documentCanUndo: Bool { !undoStack.isEmpty && isEditable && viewMode != .reading }
    public var documentCanRedo: Bool { !redoStack.isEmpty && isEditable && viewMode != .reading }

    /// Ranges refer to the same pre-command LF projection. Validation happens
    /// before mutation; the complete replacement batch is one Undo operation.
    public func replaceProjectedRanges(
        _ edits: [(range: NSRange, replacement: String)],
        selection: NSRange? = nil,
        preserveSelectionOnUndo: Bool = false
    ) throws {
        guard isEditable, viewMode != .reading, !isComposingSource else { throw DocumentCommandError.unavailable }
        guard !edits.isEmpty else { return }
        var candidate = try ExactSourceProjection(utf8: exactUTF8ForSaving())
        try candidate.replace(edits)
        let text = candidate.projectedText
        let caret = selection ?? NSRange(location: min(selectedRange().location, (text as NSString).length), length: 0)
        _ = try candidate.sourceUTF16Range(forProjectedUTF16Range: caret)
        guard !(text as NSString).isEqual(to: rawSource) else {
            setSelectedRange(caret)
            return
        }
        applyWholeDocumentEdit(
            newRawSource: text, select: caret, sourceEdits: edits,
            preserveSelectionOnUndo: preserveSelectionOnUndo)
        _ = try exactUTF8ForSaving()
    }

    /// Host menus use the application's stable command vocabulary. This entry
    /// does not import, resolve, or write attachments; destinations are supplied
    /// only after the host's attachment workflow has admitted them.
    public func performDocumentCommand(named command: String, argument: String? = nil) throws {
        guard isEditable, viewMode != .reading, !isComposingSource else { throw DocumentCommandError.unavailable }
        guard selectedRanges.count == 1 else { throw DocumentCommandError.unsupported("multiple selections") }
        _ = try exactUTF8ForSaving()
        sourceEditRejection = nil
        let selection = selectedRange()
        let text = (rawSource as NSString).substring(with: selection)
        func replace(_ replacement: String, select: NSRange? = nil) throws {
            try replaceProjectedRanges(
                [(selection, replacement)], selection: select ?? NSRange(location: selection.location + replacement.utf16.count, length: 0))
        }
        switch command {
        case "bold": formatBold(nil)
        case "emphasis": formatItalic(nil)
        case "strikethrough": formatStrikethrough(nil)
        case "highlight": formatHighlight(nil)
        case "inlineCode":
            let longest = text.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            let fence = String(repeating: "`", count: max(1, longest + 1))
            toggleInlineWrap(open: fence, close: fence, expandToWord: false)
        case "markdownComment": toggleInlineWrap(open: "%% ", close: " %%", expandToWord: false)
        case "wikilink": formatWikilink(nil)
        case "standardLink", "linkSelectedText":
            let destination = argument ?? ""
            guard !destination.contains("\n"), !destination.contains("\r") else { throw DocumentCommandError.invalidArgument }
            let link = "[\(text)](\(destination))"
            let caret = selection.location + (text.isEmpty ? 1 : text.utf16.count + 3)
            try replace(link, select: NSRange(location: caret, length: text.isEmpty ? 0 : destination.utf16.count))
        case "annotatedWikilink":
            let target = text.isEmpty ? "Target" : text
            try replace(
                "[[\(target)]]{{Annotation}}",
                select: NSRange(location: selection.location + (text.isEmpty ? 2 : target.utf16.count + 6), length: text.isEmpty ? target.utf16.count : 10))
        case "insertInlineFootnote":
            try replace("^[\(text)]", select: NSRange(location: selection.location + 2, length: text.utf16.count))
        case "insertFootnote":
            let source = rawSource as NSString
            let regex = try NSRegularExpression(pattern: #"\[\^(\d+)\]"#)
            let used = Set(
                regex.matches(in: rawSource, range: NSRange(location: 0, length: source.length)).compactMap { Int(source.substring(with: $0.range(at: 1))) })
            var number = 1
            while used.contains(number) { number += 1 }
            let marker = "[^\(number)]"
            let content = argument ?? text
            let separator = rawSource.isEmpty ? "" : rawSource.hasSuffix("\n") ? "\n" : "\n\n"
            let prefix = separator + "[^\(number)]: "
            let definition = prefix + content + "\n"
            let edits: [(range: NSRange, replacement: String)] =
                selection.location == source.length
                ? [(selection, marker + definition)]
                : [(selection, marker), (NSRange(location: source.length, length: 0), definition)]
            let contentStart = source.length + marker.utf16.count - selection.length + prefix.utf16.count
            try replaceProjectedRanges(edits, selection: NSRange(location: contentStart, length: content.utf16.count))
        case "paragraph", "heading1", "heading2", "heading3", "heading4", "heading5", "heading6":
            let item = NSMenuItem()
            item.tag = command == "paragraph" ? 0 : Int(command.suffix(1)) ?? 1
            formatHeading(item)
        case "blockQuotation": formatBlockQuote(nil)
        case "bulletList": formatBulletedList(nil)
        case "numberedList": formatNumberedList(nil)
        case "taskList": formatChecklist(nil)
        case "fencedCode": formatCodeBlock(nil)
        case "thematicBreak": formatThematicBreak(nil)
        case "insertTable": formatTable(nil)
        case "calloutOrient", "calloutCite", "calloutConnect", "calloutState", "calloutIllustrate", "calloutQuote", "calloutFlag":
            let item = NSMenuItem()
            item.representedObject = String(command.dropFirst("callout".count)).lowercased()
            formatCallout(item)
        case "toggleTask":
            let line = 1 + (rawSource as NSString).substring(to: selection.location).filter { $0 == "\n" }.count
            guard toggleTask(atLine: line) != nil else { throw DocumentCommandError.unsupported(command) }
        case "pastePlain", "pasteMarkdown":
            guard let argument else { throw DocumentCommandError.invalidArgument }
            try replace(argument.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        case "insertImage", "insertAttachment":
            struct Attachment: Decodable {
                let alt: String
                let destination: String
            }
            guard let argument, argument.utf8.count <= 8_192,
                let attachment = try? JSONDecoder().decode(Attachment.self, from: Data(argument.utf8)),
                attachment.alt.utf16.count <= 1_024, !attachment.destination.isEmpty,
                attachment.destination.utf16.count <= 4_096,
                !attachment.destination.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "\\" }),
                attachment.destination.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) == nil
            else {
                throw DocumentCommandError.invalidArgument
            }
            let absolute = attachment.destination.hasPrefix("/")
            let path = absolute ? String(attachment.destination.dropFirst()) : attachment.destination
            guard attachment.destination.range(of: #"%(?![0-9A-Fa-f]{2})"#, options: .regularExpression) == nil,
                path.components(separatedBy: "/").allSatisfy({ component in
                    (!absolute && component == "..")
                        || (component != "." && component != ".."
                            && component.range(of: #"^[A-Za-z0-9._~%\-]+$"#, options: .regularExpression) != nil)
                }),
                !attachment.alt.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else {
                throw DocumentCommandError.invalidArgument
            }
            let selectedIsUsable = text.utf16.count <= 1_024 && !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            let label = text.isEmpty || !selectedIsUsable ? attachment.alt : text
            let escaped = label.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(
                of: "]", with: "\\]")
            try replace("\(command == "insertImage" ? "!" : "")[\(escaped)](\(attachment.destination))")
        case "tableInsertRowBefore", "tableInsertRowAfter", "tableDeleteRow", "tableInsertColumnBefore", "tableInsertColumnAfter", "tableDeleteColumn",
            "tableAlignLeft", "tableAlignCenter", "tableAlignRight":
            try performDocumentTableCommand(command)
        default: throw DocumentCommandError.unsupported(command)
        }
        if let rejection = sourceEditRejection { throw DocumentCommandError.rejected(rejection) }
        _ = try exactUTF8ForSaving()
    }

    private func performDocumentTableCommand(_ command: String) throws {
        guard let cell = tableCell(atRawOffset: selectedRange().location),
            let lines = tableLines(blockIndex: cell.blockIndex)
        else { throw DocumentCommandError.unsupported(command) }
        switch command {
        case "tableInsertRowBefore": insertTableRow(blockIndex: cell.blockIndex, at: cell.row, column: cell.column)
        case "tableInsertRowAfter": insertTableRow(blockIndex: cell.blockIndex, at: cell.row == 0 ? 2 : cell.row + 1, column: cell.column)
        case "tableDeleteRow":
            guard canDeleteTableRow(blockIndex: cell.blockIndex, row: cell.row) else { throw DocumentCommandError.unsupported(command) }
            deleteTableRow(blockIndex: cell.blockIndex, row: cell.row, column: cell.column)
        case "tableInsertColumnBefore": insertTableColumn(blockIndex: cell.blockIndex, at: cell.column, row: cell.row)
        case "tableInsertColumnAfter": insertTableColumn(blockIndex: cell.blockIndex, at: cell.column + 1, row: cell.row)
        case "tableDeleteColumn":
            guard canDeleteTableColumn(blockIndex: cell.blockIndex, column: cell.column) else { throw DocumentCommandError.unsupported(command) }
            deleteTableColumn(blockIndex: cell.blockIndex, column: cell.column, row: cell.row)
        default:
            guard lines.count > 1 else { throw DocumentCommandError.unsupported(command) }
            let separator = lines[1] as NSString
            let spans = columnSpans(in: separator)
            guard spans.indices.contains(cell.column) else { throw DocumentCommandError.unsupported(command) }
            let span = spans[cell.column]
            let raw = separator.substring(with: NSRange(location: span.start, length: span.end - span.start))
            let leading = raw.prefix { $0 == " " || $0 == "\t" }
            let trailing = raw.reversed().prefix { $0 == " " || $0 == "\t" }.reversed()
            let dashes = String(repeating: "-", count: max(3, raw.filter { $0 == "-" }.count))
            let aligned = command == "tableAlignLeft" ? ":" + dashes : command == "tableAlignRight" ? dashes + ":" : ":" + dashes + ":"
            let range = NSRange(
                location: blocks[cell.blockIndex].range.location + lines[0].utf16.count + 1 + span.start,
                length: span.end - span.start)
            let delta = leading.utf16.count + aligned.utf16.count + String(trailing).utf16.count - range.length
            let old = selectedRange()
            try replaceProjectedRanges(
                [(range, String(leading) + aligned + String(trailing))],
                selection: NSRange(location: old.location > range.location ? old.location + delta : old.location, length: old.length))
        }
    }
}
