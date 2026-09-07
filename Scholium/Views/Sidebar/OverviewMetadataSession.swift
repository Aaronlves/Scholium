import AppKit
import ScholiumContracts

struct OverviewMetadataCreator: Identifiable {
    let id: UUID
    var values: [String: String]
    var singleName: Bool

    init(value: YAMLValue? = nil, id: UUID = UUID()) {
        self.id = id
        if case .object(let object) = value {
            values = object.compactMapValues(\.scalarString)
        } else { values = [:] }
        singleName = values["literal"] != nil
    }

    var value: YAMLValue? {
        let keys = singleName ? ["literal"] : ["family", "given", "suffix", "non_dropping_particle", "dropping_particle"]
        let nonempty = values.filter { keys.contains($0.key) && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return nonempty.isEmpty ? nil : .object(nonempty.mapValues(YAMLValue.string))
    }
}

struct OverviewMetadataListValue: Identifiable {
    let id: UUID
    var text: String
    init(text: String, id: UUID = UUID()) { self.text = text; self.id = id }
}

struct OverviewMetadataDraft {
    var text = ""
    var boolean = false
    var creators: [OverviewMetadataCreator] = []
    var list: [OverviewMetadataListValue] = []
    var original: YAMLValue?

    init(_ value: YAMLValue?, kind: PropertyValueKind, retaining previous: Self? = nil) {
        original = value
        let oldCreators = previous?.creators ?? []
        let oldList = previous?.list ?? []
        switch value {
        case .array(let values):
            if kind == .creatorList {
                creators = values.enumerated().map { index, value in
                    OverviewMetadataCreator(value: value, id: oldCreators.indices.contains(index) ? oldCreators[index].id : UUID())
                }
            } else {
                list = values.compactMap(\.scalarString).enumerated().map { index, text in
                    OverviewMetadataListValue(text: text, id: oldList.indices.contains(index) ? oldList[index].id : UUID())
                }
            }
        case .boolean(let value): boolean = value
        default: text = value?.scalarString ?? ""
        }
        if kind == .creatorList && creators.isEmpty { creators = [OverviewMetadataCreator(id: previous?.creators.first?.id ?? UUID())] }
        if (kind == .textList || kind == .tags) && list.isEmpty { list = [OverviewMetadataListValue(text: "", id: previous?.list.first?.id ?? UUID())] }
    }

    func value(kind: PropertyValueKind) throws -> YAMLValue? {
        switch kind {
        case .creatorList:
            let values = creators.compactMap(\.value)
            for creator in creators where creator.value != nil && !creator.singleName {
                if (creator.values["family"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw OverviewMetadataError(String(localized: "Enter a family name or single name for this creator."))
                }
            }
            return values.isEmpty ? nil : .array(values)
        case .textList, .tags:
            let values = list.map(\.text).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return values.isEmpty ? nil : .array(values.map(YAMLValue.string))
        case .boolean: return .boolean(boolean)
        case .number:
            let number = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if number.isEmpty { return nil }
            if let integer = Int(number) { return .integer(integer) }
            if let double = Double(number), double.isFinite { return .double(double) }
            throw OverviewMetadataError(String(localized: "Enter a valid number."))
        case .mapping: return original
        default:
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .string(text)
        }
    }
}

struct OverviewMetadataError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// One Note-local edit transaction owner. Native controls own typing and focus;
/// this session serializes revision-checked commits and durable Undo/Redo.
@MainActor final class OverviewMetadataSession {
    let undoManager = UndoManager()
    var changed: (() -> Void)?
    var didCommit: (() -> Void)?
    var fields: [PropertyEditorField] = []
    var visibleKeys: [String] = []
    var drafts: [String: OverviewMetadataDraft] = [:]
    var dirtyKeys: Set<String> = []
    var composing: Set<String> = []
    private(set) var baseline: [String: YAMLValue] = [:]
    private(set) var revision: DocumentFingerprint?
    private(set) var error: (key: String?, message: String)?
    private(set) var isSaving = false
    private var saveTask: Task<Void, Never>?
    private var pendingCommit = false
    private var pendingValues: [String: YAMLValue]?
    private var registersHistory = true
    var save: (([String: YAMLValue], DocumentFingerprint?) async throws -> DocumentFingerprint?)?
    var reload: (() async throws -> (fields: [String: YAMLValue], revision: DocumentFingerprint?))?

    init() { undoManager.groupsByEvent = false }

    func configure(note: WindowDocumentLocation, catalog: NoteMetadataCatalog, visible: [String]) {
        fields = PropertyEditorModel(note: note, metadataCatalog: catalog).allFields
        // Include present archived or non-typical fields through the pure model.
        let model = PropertyEditorModel(note: note, metadataCatalog: catalog)
        fields = (visible + fields.map(\.key)).reduce(into: [PropertyEditorField]()) { result, key in
            if !result.contains(where: { $0.key == key }), let field = model.canonicalField(for: key) { result.append(field) }
        }
        if drafts.isEmpty {
            baseline = note.managedMetadataFields
            revision = note.workspaceSnapshot?.metadata?.revision
        } else if dirtyKeys.isEmpty && !isSaving && error == nil && composing.isEmpty,
                  note.workspaceSnapshot?.metadata?.revision != revision {
            baseline = note.managedMetadataFields
            revision = note.workspaceSnapshot?.metadata?.revision
            undoManager.removeAllActions()
            drafts = [:]
        }
        visibleKeys = Array(NSOrderedSet(array: visibleKeys + visible).array.compactMap { $0 as? String })
        for field in fields where drafts[field.key] == nil {
            drafts[field.key] = OverviewMetadataDraft(baseline[field.key], kind: field.valueKind)
        }
    }

    func edit(_ key: String, _ change: (inout OverviewMetadataDraft) -> Void) {
        guard fields.first(where: { $0.key == key })?.isReadOnly == false,
              var draft = drafts[key] else { return }
        change(&draft)
        removedKeys.remove(key)
        drafts[key] = draft
        dirtyKeys.insert(key)
    }

    var orderedVisibleKeys: [String] {
        let primary = ["title", "authors", "publication_date", "container_title", "type", "publisher", "publisher_place", "volume", "issue", "pages", "doi", "url", "accessed_date"]
        return visibleKeys.sorted { left, right in
            let lhs = primary.firstIndex(of: left) ?? (primary.count + (visibleKeys.firstIndex(of: left) ?? 0))
            let rhs = primary.firstIndex(of: right) ?? (primary.count + (visibleKeys.firstIndex(of: right) ?? 0))
            return lhs < rhs
        }
    }

    private var removedKeys: Set<String> = []

    func requestCommit() {
        guard composing.isEmpty else { return }
        do { pendingValues = try candidate() }
        catch { changed?(); return }
        pendingCommit = true
        guard saveTask == nil else { return }
        saveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drain()
            self.saveTask = nil
        }
    }

    func flush() async throws {
        guard composing.isEmpty else {
            throw OverviewMetadataError(String(localized: "Finish text composition before leaving this field."))
        }
        requestCommit()
        while let task = saveTask { await task.value }
        if let error { throw OverviewMetadataError(error.message) }
    }

    private func candidate() throws -> [String: YAMLValue] {
        var result = baseline
        for key in dirtyKeys {
            guard let field = fields.first(where: { $0.key == key }), let draft = drafts[key] else { continue }
            do { result[key] = removedKeys.contains(key) ? nil : try draft.value(kind: field.valueKind) }
            catch {
                self.error = (key, error.localizedDescription)
                throw error
            }
        }
        return result
    }

    private func drain() async {
        while pendingCommit && composing.isEmpty {
            pendingCommit = false
            do {
                guard let candidate = pendingValues else { return }
                pendingValues = nil
                if candidate == baseline {
                    error = nil
                    for key in Array(dirtyKeys) {
                        guard let field = fields.first(where: { $0.key == key }), let draft = drafts[key] else { continue }
                        if (try? draft.value(kind: field.valueKind)) == baseline[key] { dirtyKeys.remove(key); removedKeys.remove(key) }
                    }
                    changed?(); return
                }
                guard let save else { return }
                isSaving = true
                let previous = baseline
                let committedKeys = dirtyKeys
                let shouldRegister = registersHistory
                registersHistory = true
                let acknowledged = try await save(candidate, revision)
                baseline = candidate
                revision = acknowledged
                isSaving = false
                error = nil
                for key in committedKeys {
                    guard let field = fields.first(where: { $0.key == key }), let draft = drafts[key] else { continue }
                    let current = removedKeys.contains(key) ? nil : try? draft.value(kind: field.valueKind)
                    if current == candidate[key] { dirtyKeys.remove(key); removedKeys.remove(key) }
                }
                if shouldRegister { registerHistory(previous, inverse: candidate) }
                didCommit?()
                changed?()
            } catch {
                isSaving = false
                pendingCommit = false
                if self.error == nil { self.error = (dirtyKeys.first, error.localizedDescription) }
                changed?()
                return
            }
        }
    }

    func undoCommitted() async throws {
        try await flush()
        undoManager.undo()
        try await flush()
    }

    func redoCommitted() async throws {
        try await flush()
        undoManager.redo()
        try await flush()
    }

    private func registerHistory(_ target: [String: YAMLValue], inverse: [String: YAMLValue]) {
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { owner in owner.restoreHistory(target, inverse: inverse) }
        undoManager.setActionName(String(localized: "Edit Metadata"))
        undoManager.endUndoGrouping()
    }

    private func restoreHistory(_ target: [String: YAMLValue], inverse: [String: YAMLValue]) {
        registerHistory(inverse, inverse: target)
        registersHistory = false
        let keys = Set(target.keys).union(inverse.keys).filter { target[$0] != inverse[$0] }
        applyValues(target, keys: Set(keys))
        changed?()
        requestCommit()
    }

    private func applyValues(_ values: [String: YAMLValue], keys: Set<String>) {
        for key in keys {
            guard let field = fields.first(where: { $0.key == key }) else { continue }
            drafts[key] = OverviewMetadataDraft(values[key], kind: field.valueKind, retaining: drafts[key])
            dirtyKeys.insert(key)
            if values[key] == nil { removedKeys.insert(key) } else { removedKeys.remove(key) }
            if !visibleKeys.contains(key) { visibleKeys.append(key) }
        }
    }

    func cancelDraft(_ key: String) {
        guard !isSaving, let field = fields.first(where: { $0.key == key }) else { return }
        drafts[key] = OverviewMetadataDraft(baseline[key], kind: field.valueKind, retaining: drafts[key])
        dirtyKeys.remove(key); removedKeys.remove(key)
        if error?.key == key { error = nil }
        changed?()
    }

    func reloadCurrent() {
        guard !isSaving, let reload else { return }
        Task { @MainActor in
            do {
                let loaded = try await reload()
                baseline = loaded.fields; revision = loaded.revision
                dirtyKeys.removeAll(); removedKeys.removeAll(); composing.removeAll()
                error = nil; undoManager.removeAllActions()
                for field in fields { drafts[field.key] = OverviewMetadataDraft(baseline[field.key], kind: field.valueKind, retaining: drafts[field.key]) }
                changed?()
            } catch { self.error = (self.error?.key, error.localizedDescription); changed?() }
        }
    }
}
