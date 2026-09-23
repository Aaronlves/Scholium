// Scholium experiment: exact source provenance for Edmund's LF editing projection.
import AppKit

extension EditorTextView {
    public enum ExactSourceError: Error, LocalizedError {
        case unavailable(String)
        public var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return reason
            }
        }
    }

    /// Load exact UTF-8 bytes while retaining Edmund's LF-only display model.
    public func loadExactUTF8(_ bytes: Data) throws {
        let projection = try ExactSourceProjection(utf8: bytes)
        loadContent(projection.projectedText, unwrapHardWrapping: false)
        exactSourceProjection = projection
        committedExactSource = projection
        sourceRevision &+= 1
        scheduleSourceStateNotification()
        (textStorage as? EditorTextStorage)?.willReplaceSource = { [weak self] range, replacement in
            // This editor and its TextKit storage are mutated only on the UI thread.
            MainActor.assumeIsolated {
                guard let self, !self.isUpdating, !self.isUndoRedoing else { return }
                self.trackExactReplacement(range: range, replacement: replacement)
            }
        }
    }

    /// A save candidate is available only after a committed, fully mapped edit.
    public func exactUTF8ForSaving() throws -> Data {
        // AppKit can mutate storage without delivering didChangeText until a
        // later run-loop turn. Flush only a completely mapped, committed edit.
        // Never use this to guess through an unmapped or composing change.
        if !isComposingSource, exactSourceFailure == nil,
            let projection = exactSourceProjection, let storage = textStorage?.string,
            (projection.projectedText as NSString).isEqual(to: storage),
            !(storage as NSString).isEqual(to: rawSource)
        {
            didChangeText()
        }
        guard !isComposingSource, (textStorage?.string as NSString?)?.isEqual(to: rawSource) == true else {
            throw ExactSourceError.unavailable("请先完成当前输入；编辑内容尚未同步。")
        }
        guard let projection = exactSourceProjection else {
            throw ExactSourceError.unavailable("此会话未载入原始字节。")
        }
        guard exactSourceFailure == nil,
            (projection.projectedText as NSString).isEqual(to: rawSource)
        else {
            throw ExactSourceError.unavailable("此操作尚未建立可靠的源文对应，已阻止保存。请撤销该操作。")
        }
        return projection.utf8
    }

    /// A lightweight transaction token, not a content hash, disk revision or
    /// persisted snapshot. Equivalent editing transactions may advance it;
    /// presentation-only changes do not. Hosts compare bytes at their save boundary.
    public struct SourceState: Equatable, Sendable {
        public let revision: UInt64
        public let isComposing: Bool
        public let canCapture: Bool
    }

    public var sourceState: SourceState {
        SourceState(
            revision: sourceRevision, isComposing: isComposingSource,
            canCapture: exactSourceProjection != nil && exactSourceFailure == nil
                && !isComposingSource
                && (textStorage?.string as NSString?)?.isEqual(to: rawSource) == true)
    }

    func scheduleSourceStateNotification() {
        guard !sourceNotificationPending else { return }
        sourceNotificationPending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.sourceNotificationPending = false
            self.applyPendingNativeAppearance()
            self.onSourceStateChange?(self.sourceState)
        }
    }

    func trackExactReplacement(range: NSRange, replacement: String) {
        scheduleSourceStateNotification()
        guard var projection = exactSourceProjection, exactSourceFailure == nil else { return }
        guard (projection.projectedText as NSString).isEqual(to: textStorage?.string ?? "") else {
            exactSourceFailure = "Storage/source projection mismatch"
            return
        }
        do {
            try projection.replace(in: range, with: replacement)
            exactSourceProjection = projection
        } catch { exactSourceFailure = String(describing: error) }
    }

    /// Ranges describe non-overlapping edits in the pre-command buffer. Validate
    /// the complete batch before publishing provenance; never guess a text diff.
    @discardableResult
    func trackExactReplacements(_ edits: [(range: NSRange, replacement: String)]) -> Bool {
        guard exactSourceFailure == nil else { return false }
        guard let original = exactSourceProjection else {
            // The native application always uses exact sessions, but callers
            // of the underlying LF text model receive the same capacity rule.
            do {
                var candidate = try ExactSourceProjection(utf8: Data(rawSource.utf8))
                try candidate.replace(edits)
                return true
            } catch {
                rejectSourceEdit(error)
                return false
            }
        }
        guard (original.projectedText as NSString).isEqual(to: rawSource) else {
            exactSourceFailure = "Command/source projection mismatch"
            return false
        }
        do {
            var candidate = original
            try candidate.replace(edits)
            exactSourceProjection = candidate
            return true
        } catch {
            rejectSourceEdit(error)
            return false
        }
    }

    func rejectSourceEdit(_ error: any Error) {
        sourceEditRejection = error.localizedDescription
        onSourceEditRejected?(error.localizedDescription)
    }

    /// A line-wise transform owns each line's content, but not its terminator.
    /// Callers supply the correspondence by line index, never by text matching.
    func lineContentEdits(start: Int, oldLines: [String], newLines: [String])
        -> [(range: NSRange, replacement: String)]
    {
        precondition(oldLines.count == newLines.count)
        var offset = start
        return zip(oldLines, newLines).map { old, new in
            defer { offset += (old as NSString).length + 1 }
            return (NSRange(location: offset, length: (old as NSString).length), new)
        }
    }

    func synchronizeExactSourceCheckpoint() {
        guard let projection = exactSourceProjection else { return }
        if !(projection.projectedText as NSString).isEqual(to: rawSource) {
            exactSourceFailure = "Programmatic edit has no exact transaction mapping"
        }
        committedExactSource = projection
        committedExactSourceFailure = exactSourceFailure
    }

    func makeUndoSnapshot(cursor: Int, selection: NSRange? = nil) -> UndoSnapshot {
        UndoSnapshot(
            rawSource: rawSource, cursorInRaw: cursor, selectionInRaw: selection,
            exactSource: committedExactSource, exactSourceFailure: committedExactSourceFailure)
    }
}
