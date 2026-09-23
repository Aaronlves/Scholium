import AppKit
import Foundation
import ScholiumContracts
import ScholiumEditor

/// Commands, search and research selections operate on the retained native
/// session. Editable coordinates are projected UTF-16; saved/research ranges
/// always map back to the exact source of the same synchronous snapshot.
extension MarkdownEditorSession {
    func perform(_ command: MarkdownEditorCommand, argument: String? = nil) async throws {
        guard isReady, isLoaded, !isComposing else { throw SessionError.unavailable }
        _ = try reconcileNativeSource()
        guard nativeCommandIsPermitted(command) else { throw SessionError.operationRejected("This command is unavailable at the current selection.") }
        let value =
            command == .pastePlain || command == .pasteMarkdown
            ? argument ?? NSPasteboard.general.string(forType: .string) : argument
        try nativeEditor.performDocumentCommand(named: command.rawValue, argument: value)
        _ = try reconcileNativeSource()
        updateNativeInteraction()
    }

    private func commandSemanticDocument() -> (document: NoteDocument, semantic: MarkdownSemanticDocument) {
        if let cached = commandSemanticCache, cached.source.utf8.elementsEqual(checkedSource.utf8) {
            return (cached.document, cached.semantic)
        }
        let document = NoteDocument(relativePath: documentID, rawContent: checkedSource)
        let semantic = MarkdownSemanticDocument(parsing: document)
        commandSemanticCache = (checkedSource, document, semantic)
        return (document, semantic)
    }

    func nativeCommandIsPermitted(_ command: MarkdownEditorCommand) -> Bool {
        nativeAvailableCommands().contains(command)
    }

    private func nativeAvailableCommands() -> [MarkdownEditorCommand] {
        guard isReady, isLoaded, nativeEditor.isEditable, nativeEditor.viewMode != .reading,
            !isComposing, nativeEditor.selectedRanges.count == 1,
            let projection = try? ExactSourceProjection(utf8: Data(checkedSource.utf8)),
            let selection = try? projection.sourceUTF16Range(forProjectedUTF16Range: nativeEditor.selectedRange())
        else { return [] }
        let (document, semantic) = commandSemanticDocument()
        let frontmatterEnd = document.hasProvableBodyBoundary ? document.bodyUTF16Offset : checkedSource.utf16.count
        if selection.location < frontmatterEnd {
            return selection.upperBound <= frontmatterEnd ? [.pastePlain, .pasteMarkdown] : []
        }
        func overlaps(_ span: NSRange) -> Bool {
            selection.length == 0
                ? selection.location >= span.location && selection.location < span.upperBound
                : NSIntersectionRange(selection, span).length > 0
        }
        let literals =
            semantic.blocks.filter { $0.kind == .code || $0.kind == .html }.map(\.span.nsRange)
            + semantic.inlines.filter { $0.kind == .code }.map(\.span.nsRange)
            + semantic.mathExpressions.map(\.span.nsRange)
            + MarkdownSemanticParser.commentRanges(in: document).map { NSRange(location: $0.lowerBound, length: $0.count) }
        guard !literals.contains(where: overlaps) else { return [] }
        let table = nativeEditor.documentTablePosition
        let text = nativeEditor.rawSource as NSString
        let line = text.substring(with: text.lineRange(for: nativeEditor.selectedRange()))
        let isTask = line.range(of: #"^[ \t]*(?:[-+*]|\d{1,9}[.)])[ \t]+\[[ xX]\]"#, options: .regularExpression) != nil
        return MarkdownEditorCommand.allCases.filter { command in
            if command.rawValue.hasPrefix("table") {
                guard let table else { return false }
                if command == .tableDeleteRow { return table.canDeleteRow }
                if command == .tableDeleteColumn { return table.canDeleteColumn }
            }
            if command == .linkSelectedText { return nativeEditor.selectedRange().length > 0 }
            if command == .toggleTask { return isTask }
            return true
        }
    }

    func nativeContext() -> MarkdownEditorContext {
        let selections = currentValidSelectionRanges()
        let table = nativeEditor.documentTablePosition.map {
            MarkdownEditorTablePosition(row: $0.row, column: $0.column, rowCount: $0.rowCount, columnCount: $0.columnCount)
        }
        let semantic = commandSemanticDocument().semantic
        let projection = try? ExactSourceProjection(utf8: Data(checkedSource.utf8))
        let sourceRange = try? projection?.sourceUTF16Range(forProjectedUTF16Range: nativeEditor.selectedRange())
        func contains(_ span: SourceSpan) -> Bool {
            guard let sourceRange else { return false }
            return sourceRange.location >= span.utf16LowerBound && sourceRange.upperBound <= span.utf16UpperBound
        }
        let inlineNames: [MarkdownInlineKind: String] = [
            .strong: "StrongEmphasis", .emphasis: "Emphasis", .strikethrough: "Strikethrough", .highlight: "Highlight", .code: "InlineCode", .link: "Link",
            .image: "Image",
        ]
        let inline = semantic.inlines.filter { contains($0.span) }.compactMap { inlineNames[$0.kind] }
        var block = semantic.blocks.filter { contains($0.span) }.map { value in
            switch value.kind {
            case .heading: "ATXHeading\(semantic.headings.first(where: { $0.span == value.span })?.level ?? 1)"
            case .blockQuote: "Blockquote"
            case .code: "FencedCode"
            case .unorderedList: "BulletList"
            case .orderedList: "OrderedList"
            case .table: "Table"
            default: value.kind.rawValue
            }
        }
        if semantic.callouts.contains(where: { contains($0.span) }) { block.append("Callout") }
        return MarkdownEditorContext(
            selections: selections, activeInlineConstructs: Array(Set(inline)).sorted(),
            activeBlockConstructs: Array(Set(block)).sorted(), tablePosition: table,
            composing: isComposing, availableCommands: nativeAvailableCommands(),
            undoLabel: nativeEditor.documentCanUndo ? "Undo Editing" : nil,
            redoLabel: nativeEditor.documentCanRedo ? "Redo Editing" : nil)
    }

    func performDocumentFind(_ query: DocumentFindQuery) async throws -> DocumentFindResult {
        guard isReady, isLoaded, !isComposing else { throw SessionError.unavailable }
        _ = try reconcileNativeSource()
        var matches = try NativeDocumentFind.matches(in: nativeEditor.rawSource, query: query)
        let selection = nativeEditor.selectedRange()
        var target: NSRange?
        func forward(_ boundary: Int, in ranges: [NSRange]) -> NSRange? {
            ranges.first { $0.location >= boundary } ?? ranges.first
        }
        switch query.action {
        case .present: break
        case .update: target = forward(selection.location, in: matches)
        case .next: target = forward(selection.upperBound, in: matches)
        case .previous: target = matches.last { $0.upperBound <= selection.location } ?? matches.last
        case .replaceCurrent, .replaceAll:
            guard nativeEditor.isEditable, nativeEditor.viewMode != .reading else { throw SessionError.unavailable }
            let replacement = query.replacement.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            let replacing =
                query.action == .replaceAll
                ? matches
                : (matches.first(where: { $0 == selection }) ?? forward(selection.location, in: matches)).map { [$0] } ?? []
            try nativeEditor.replaceProjectedRanges(replacing.map { ($0, replacement) })
            _ = try reconcileNativeSource()
            matches = try NativeDocumentFind.matches(in: nativeEditor.rawSource, query: query)
            target = forward(query.action == .replaceCurrent ? (replacing.first?.location ?? 0) + replacement.utf16.count : selection.location, in: matches)
        }
        if let target {
            nativeEditor.setSelectedRange(target)
            nativeEditor.scrollRangeToVisible(target)
        }
        updateNativeInteraction()
        let index = matches.firstIndex(of: nativeEditor.selectedRange())
        return DocumentFindResult(current: index.map { $0 + 1 } ?? 0, total: matches.count)
    }

    func clearDocumentFind() async {
        guard isReady, isLoaded else { return }
        nativeEditor.window?.makeFirstResponder(nativeEditor)
    }

    func replacePassage(
        expectedText: String, fromUTF16: Int, toUTF16: Int,
        replacement: String, preserveSelection: Bool
    ) throws {
        guard isReady, isLoaded, !isComposing else { throw SessionError.unavailable }
        let snapshot = try reconcileNativeSource()
        guard snapshot.text.utf8.elementsEqual(expectedText.utf8), fromUTF16 >= 0, toUTF16 >= fromUTF16 else {
            throw SessionError.staleRequest
        }
        let projection = try ExactSourceProjection(utf8: Data(snapshot.text.utf8))
        let range = try projection.projectedUTF16Range(forSourceUTF16Range: NSRange(location: fromUTF16, length: toUTF16 - fromUTF16))
        let normalized = replacement.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let oldSelection = nativeEditor.selectedRange()
        let nextSelection =
            preserveSelection
            ? NativeDocumentSelectionMapping.map(oldSelection, replacing: range, replacementUTF16Length: normalized.utf16.count)
            : NSRange(location: range.location + normalized.utf16.count, length: 0)
        try nativeEditor.replaceProjectedRanges(
            [(range, normalized)], selection: nextSelection,
            preserveSelectionOnUndo: preserveSelection)
        _ = try reconcileNativeSource()
        updateNativeInteraction()
    }

    func selectedSourceSnapshot() async throws -> MarkdownSourceSelectionSnapshot {
        try await writingContextSnapshot(mode: .selectionOnly).snapshot
    }

    func writingContextSnapshot(mode: MarkdownWritingContextCaptureMode) async throws -> (
        snapshot: MarkdownSourceSelectionSnapshot, point: MarkdownEditorInsertionPoint?
    ) {
        guard !isComposing, isReady, isLoaded else { throw SessionError.unavailable }
        let source = try reconcileNativeSource().text
        let selections = currentValidSelectionRanges()
        let snapshot = try MarkdownWritingContextProjection.capture(source: source, selections: selections, mode: mode)
        let point = selections.first.flatMap { selection -> MarkdownEditorInsertionPoint? in
            guard !selection.isNonempty, selections.count == 1 else { return nil }
            return .init(sessionID: sessionID, documentID: documentID, generation: generation, selection: selection)
        }
        return (snapshot, point)
    }

    func acceptsInsertionPoint(_ point: MarkdownEditorInsertionPoint) -> Bool {
        !isComposing && isReady && isLoaded && point.sessionID == sessionID && point.documentID == documentID
            && point.generation == generation && currentValidSelectionRanges() == [point.selection]
            && nativeEditor.isEditable && nativeEditor.viewMode != .reading
    }

    func insertReference(_ target: String, at point: MarkdownEditorInsertionPoint) async throws {
        _ = try reconcileNativeSource()
        guard acceptsInsertionPoint(point), nativeCommandIsPermitted(.wikilink), !target.isEmpty,
            !target.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "]" || $0 == "[" })
        else { throw SessionError.invalidResult }
        let insertion = "[[\(target)]]"
        try nativeEditor.replaceProjectedRanges(
            [(NSRange(location: point.selection.head, length: 0), insertion)],
            selection: NSRange(location: point.selection.head + insertion.utf16.count, length: 0))
        _ = try reconcileNativeSource()
        updateNativeInteraction()
    }

    func passageSourceSnapshot(expectedSelections: [MarkdownEditorSelectionRange]?, expectedGeneration: Int) async throws -> MarkdownSourceSelectionSnapshot {
        guard !isComposing, isReady, isLoaded else { throw SessionError.unavailable }
        let source = try reconcileNativeSource().text
        let selections = currentValidSelectionRanges()
        guard expectedGeneration == generation, expectedSelections == selections,
            selections.count == 1, let selection = selections.first
        else { throw SessionError.invalidResult }
        if selection.isNonempty {
            let captured = try MarkdownWritingContextProjection.capture(source: source, selections: selections, mode: .selectionOnly)
            guard
                let span = try? ParagraphAnchorPlanner.paragraph(
                    in: NoteDocument(relativePath: documentID, rawContent: source), atUTF16: captured.sourceRange.utf16LowerBound)
            else { return captured }
            return DocumentPassageSnapshot.includingParagraphIdentity(captured, paragraphSpan: span)
        }
        let projection = try ExactSourceProjection(utf8: Data(source.utf8))
        let offset = try projection.sourceUTF16Range(forProjectedUTF16Range: NSRange(location: selection.head, length: 0)).location
        let span = try ParagraphAnchorPlanner.paragraph(in: NoteDocument(relativePath: documentID, rawContent: source), atUTF16: offset)
        guard let snapshot = DocumentPassageSnapshot.capture(source: source, range: span.nsRange) else { throw SessionError.invalidResult }
        return snapshot
    }

    func currentSelection(for expectedDocumentID: String? = nil, in source: String? = nil) async throws -> MarkdownReviewSelection? {
        guard expectedDocumentID == nil || expectedDocumentID == documentID, isReady, isLoaded, !isComposing else { throw SessionError.unavailable }
        let snapshot = try reconcileNativeSource()
        guard source.map({ $0.utf8.elementsEqual(snapshot.text.utf8) }) ?? true else { throw SessionError.staleRequest }
        let selection = nativeEditor.selectedRange()
        guard selection.length > 0 else { return nil }
        let projection = try ExactSourceProjection(utf8: Data(snapshot.text.utf8))
        let range = try projection.sourceUTF16Range(forProjectedUTF16Range: selection)
        guard range.length <= 2_000 else { throw SessionError.selectionTooLong }
        let exact = snapshot.text as NSString
        let prefix = exact.substring(to: range.location)
        let excerpt = exact.substring(with: range)
        let projected = nativeEditor.rawSource as NSString
        let startLine = 1 + projected.substring(to: selection.location).filter { $0 == "\n" }.count
        let endLine = startLine + projected.substring(with: selection).filter { $0 == "\n" }.count
        return MarkdownReviewSelection(
            startLine: startLine, endLine: endLine, excerpt: excerpt,
            utf16LowerBound: range.location, utf16UpperBound: range.upperBound,
            contextBefore: String(prefix.suffix(48)), contextAfter: String(exact.substring(from: range.upperBound).prefix(48)))
    }
}

enum NativeDocumentFind {
    static func matches(in source: String, query: DocumentFindQuery) throws -> [NSRange] {
        guard !query.query.isEmpty else { return [] }
        let text = query.query.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let escaped = NSRegularExpression.escapedPattern(for: text)
        let pattern = query.wholeWord ? "(?<![\\p{L}\\p{M}\\p{N}_])" + escaped + "(?![\\p{L}\\p{M}\\p{N}_])" : escaped
        let expression = try NSRegularExpression(pattern: pattern, options: query.caseSensitive ? [] : [.caseInsensitive])
        return expression.matches(in: source, range: NSRange(location: 0, length: source.utf16.count)).map(\.range)
    }
}

/// Preserves the selected passage as source before it moves. An insertion at
/// the start is outside the selection; one at its end is outside too. A caret
/// at an insertion follows the inserted text. Replaced interiors map to the
/// replacement's corresponding edge.
enum NativeDocumentSelectionMapping {
    static func map(_ selection: NSRange, replacing edit: NSRange, replacementUTF16Length: Int) -> NSRange {
        let delta = replacementUTF16Length - edit.length
        let newEnd = edit.location + replacementUTF16Length
        func endpoint(_ offset: Int, isStart: Bool) -> Int {
            if offset < edit.location { return offset }
            if offset > edit.upperBound { return offset + delta }
            if edit.length == 0 { return isStart ? newEnd : edit.location }
            if offset == edit.location { return edit.location }
            if offset == edit.upperBound { return newEnd }
            return isStart ? edit.location : newEnd
        }
        if selection.length == 0 {
            let position =
                selection.location >= edit.location && selection.location <= edit.upperBound
                ? newEnd : endpoint(selection.location, isStart: true)
            return NSRange(location: position, length: 0)
        }
        let start = endpoint(selection.location, isStart: true)
        let end = endpoint(selection.upperBound, isStart: false)
        return NSRange(location: start, length: max(0, end - start))
    }
}
