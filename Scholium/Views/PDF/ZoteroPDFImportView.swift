import ScholiumContracts
import SwiftUI

/// Presentation and cancellation belong to this sheet; the captured Note and
/// portable copy transaction remain with the originating window's import owner.
struct ZoteroPDFImportView: View {
    @StateObject private var model: ZoteroPDFImportPickerModel
    @Environment(\.dismiss) private var dismiss
    private let onBack: (() -> Void)?
    private let chooseFile: (() -> Void)?

    init(
        search: @escaping ZoteroPDFImportPickerModel.Search,
        attachments: @escaping ZoteroPDFImportPickerModel.Attachments,
        resolve: @escaping ZoteroPDFImportPickerModel.Resolve,
        importPDF: @escaping ZoteroPDFImportPickerModel.Import,
        resolveLocalCopy: @escaping ZoteroPDFImportPickerModel.ResolveLocalCopy,
        importLocalCopy: @escaping ZoteroPDFImportPickerModel.ImportLocalCopy,
        onBack: (() -> Void)? = nil,
        chooseFile: (() -> Void)? = nil
    ) {
        _model = StateObject(
            wrappedValue: ZoteroPDFImportPickerModel(
                search: search, attachments: attachments, resolve: resolve, importPDF: importPDF,
                resolveLocalCopy: resolveLocalCopy, importLocalCopy: importLocalCopy))
        self.onBack = onBack
        self.chooseFile = chooseFile
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Import PDF from Zotero").font(.headline).accessibilityAddTraits(.isHeader)
                    Text("Import a separate copy into this Triptych. Highlights and comments stay in Scholium's copy; Zotero annotations are not imported.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        TextField("Search Zotero Library", text: $model.query)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Search Zotero Library")
                            .accessibilityIdentifier("scholium.pdf.zotero.search")
                            .onSubmit { model.search() }
                        Button("Search") { model.search() }
                            .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.phase == .importing)
                    }.disabled(model.phase == .importing)

                    List(selection: Binding(get: { model.selectedHitID }, set: { model.selectItem($0) })) {
                        ForEach(model.hits) { hit in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: hit.item.title.isEmpty ? hit.item.key : hit.item.title).lineLimit(2)
                                if !hit.item.authors.isEmpty {
                                    Text(verbatim: hit.item.authors.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Text(verbatim: hit.library.name).font(.caption).foregroundStyle(.secondary)
                            }.tag(hit.id).help(hit.item.key)
                        }
                    }
                    .overlay {
                        if model.hits.isEmpty, model.phase != .searching, model.error == nil {
                            if model.hasSearched {
                                Text("No Matching Zotero Items").foregroundStyle(.secondary)
                            } else {
                                Text("Search for a Zotero Item").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 130)
                    .disabled(model.phase == .importing)
                    .accessibilityLabel("Zotero Items")
                    .accessibilityIdentifier("scholium.pdf.zotero.items")

                    Text("PDF Attachments").font(.subheadline).accessibilityAddTraits(.isHeader)
                    List(selection: Binding(get: { model.selectedAttachmentID }, set: { model.selectAttachment($0) })) {
                        ForEach(model.sources) { source in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: source.title.isEmpty ? source.filename : source.title).lineLimit(2)
                                Text(verbatim: source.filename).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                if model.hasAttachmentLabelCollision(source) {
                                    HStack(spacing: 4) {
                                        Text("Attachment Key")
                                        Text(verbatim: attachmentKey(source))
                                    }.font(.caption).foregroundStyle(.secondary)
                                }
                            }.tag(source.id).help(attachmentHelp(source))
                        }
                    }
                    .overlay {
                        if model.sources.isEmpty, model.phase != .attachments, model.selectedHitID != nil, model.error == nil {
                            Text("No PDF Attachments").foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 100)
                    .disabled(model.phase != nil)
                    .accessibilityLabel("PDF Attachments")
                    .accessibilityIdentifier("scholium.pdf.zotero.attachments")

                    if let candidate = model.localCopyCandidate {
                        localCopyConfirmation(candidate)
                    }

                    if let error = model.error {
                        Text(verbatim: error).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            .accessibilityIdentifier("scholium.pdf.zotero.error")
                    }
                }.padding(20)
            }
            footer.padding(20)
        }
        .frame(minWidth: 440, idealWidth: 560, minHeight: 480, idealHeight: 600)
        .onChange(of: model.completed) { _, completed in if completed { dismiss() } }
        .interactiveDismissDisabled(model.phase == .importing)
        .onDisappear { model.invalidatePresentation() }
        .tint(nil as Color?)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let phase = model.phase {
                HStack {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                    Text(verbatim: phase.label).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                if let onBack {
                    Button("Back") { if model.cancel() { onBack() } }.disabled(model.phase == .importing)
                }
                if let chooseFile {
                    Button("Choose PDF File…") { if model.cancel() { chooseFile() } }.disabled(model.phase == .importing)
                }
                if model.canRetryLocalCopy { Button("Retry File") { model.retryLocalCopy() } }
                Spacer(minLength: 0)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") {
                    guard model.cancel() else { return }
                    dismiss()
                }.keyboardShortcut(.cancelAction).disabled(model.phase == .importing)
                Button {
                    model.importSelection()
                } label: {
                    if model.isLocalCopySelected { Text("Import Local Copy") } else { Text("Import Copy") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canImport)
                .accessibilityIdentifier("scholium.pdf.zotero.import")
            }
        }
    }

    private func localCopyConfirmation(_ candidate: ZoteroPDFLocalCopyCandidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Local PDF Copy").font(.subheadline).accessibilityAddTraits(.isHeader)
            Text(
                "This connection cannot identify the Zotero database. Import only the local file shown below; no Zotero bibliography, links, source mapping, or sync will be retained."
            )
            .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("Observed Zotero Item").font(.caption).foregroundStyle(.secondary)
            Text(verbatim: candidate.observation.item.title.isEmpty ? candidate.observation.item.key : candidate.observation.item.title)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: candidate.observation.library.name).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: candidate.originalURL.lastPathComponent).font(.callout)
            Text(verbatim: candidate.originalURL.path).font(.caption).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("scholium.pdf.zotero.localPath")
            Toggle("I confirm importing this local file without retained Zotero provenance.", isOn: $model.localCopyAcknowledged)
                .disabled(model.phase != nil)
                .accessibilityIdentifier("scholium.pdf.zotero.localAcknowledgment")
        }
    }

    private func attachmentHelp(_ option: ZoteroPDFImportOption) -> String {
        switch option {
        case .verifiedSource(let source): source.pdfReference.url.absoluteString
        case .localCopy(let observation): observation.attachmentKey
        }
    }

    private func attachmentKey(_ option: ZoteroPDFImportOption) -> String {
        switch option {
        case .verifiedSource(let source): source.attachmentKey
        case .localCopy(let observation): observation.attachmentKey
        }
    }
}

/// The request generation is independent of cancellation: late completions can
/// never replace a newer selection or publish after the sheet is dismissed.
@MainActor
final class ZoteroPDFImportPickerModel: ObservableObject {
    typealias Search = @Sendable (String) async throws -> [ZoteroSearchHit]
    typealias Attachments = @Sendable (ZoteroSearchHit) async throws -> [ZoteroPDFImportOption]
    typealias Resolve = @Sendable (ZoteroPDFSource) async throws -> ZoteroPDFImportCandidate
    typealias Import = @MainActor (ZoteroPDFImportCandidate) async throws -> Void
    typealias ResolveLocalCopy = @Sendable (ZoteroPDFLocalCopyObservation) async throws -> ZoteroPDFLocalCopyCandidate
    typealias ImportLocalCopy = @MainActor (ZoteroPDFLocalCopyCandidate) async throws -> Void

    enum Phase: Equatable {
        case searching
        case attachments
        case resolvingLocalCopy
        case importing

        var label: String {
            switch self {
            case .searching: ScholiumL10n.string("Searching Zotero")
            case .attachments: ScholiumL10n.string("Reading PDF Attachments")
            case .resolvingLocalCopy: ScholiumL10n.string("Locating Local PDF")
            case .importing: ScholiumL10n.string("Importing PDF Copy")
            }
        }
    }

    @Published var query = ""
    @Published private(set) var hits: [ZoteroSearchHit] = []
    @Published private(set) var selectedHitID: String?
    @Published private(set) var sources: [ZoteroPDFImportOption] = []
    @Published private(set) var selectedAttachmentID: String?
    @Published private(set) var localCopyCandidate: ZoteroPDFLocalCopyCandidate?
    @Published var localCopyAcknowledged = false
    @Published private(set) var phase: Phase?
    @Published private(set) var hasSearched = false
    @Published private(set) var completed = false
    @Published private(set) var error: String?

    var selectedSource: ZoteroPDFImportOption? { sources.first { $0.id == selectedAttachmentID } }
    var isLocalCopySelected: Bool {
        if let selectedSource, case .localCopy = selectedSource { return true }
        return false
    }
    var canImport: Bool {
        isPresented && !completed && phase == nil && selectedSource != nil
            && (!isLocalCopySelected || (localCopyCandidate != nil && localCopyAcknowledged))
    }
    var canRetryLocalCopy: Bool { isPresented && !completed && phase == nil && isLocalCopySelected && localCopyCandidate == nil }

    func hasAttachmentLabelCollision(_ option: ZoteroPDFImportOption) -> Bool {
        sources.contains { $0.id != option.id && $0.title == option.title && $0.filename == option.filename }
    }

    private let searchItems: Search
    private let attachmentSources: Attachments
    private let resolveSource: Resolve
    private let importPDF: Import
    private let resolveLocalCopy: ResolveLocalCopy
    private let importLocalCopy: ImportLocalCopy
    private var operation: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var isPresented = true

    #if DEBUG
        var operationForTesting: Task<Void, Never>? { operation }
    #endif

    init(
        search: @escaping Search, attachments: @escaping Attachments, resolve: @escaping Resolve, importPDF: @escaping Import,
        resolveLocalCopy: @escaping ResolveLocalCopy, importLocalCopy: @escaping ImportLocalCopy
    ) {
        searchItems = search
        attachmentSources = attachments
        resolveSource = resolve
        self.importPDF = importPDF
        self.resolveLocalCopy = resolveLocalCopy
        self.importLocalCopy = importLocalCopy
    }

    func search() {
        guard isPresented, !completed, phase != .importing else { return }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, needle.utf8.count <= 512 else { return }
        let ticket = start(.searching)
        hits = []
        selectedHitID = nil
        sources = []
        selectedAttachmentID = nil
        clearLocalCopyConfirmation()
        hasSearched = true
        operation = Task { @MainActor [weak self, searchItems] in
            do {
                let hits = try await searchItems(needle)
                try Task.checkCancellation()
                guard let self, self.generation == ticket else { return }
                self.hits = hits
                self.finish(ticket)
            } catch {
                self?.fail(error, ticket: ticket)
            }
        }
    }

    func selectItem(_ id: String?) {
        guard isPresented, !completed, phase != .importing, selectedHitID != id else { return }
        selectedHitID = id
        sources = []
        selectedAttachmentID = nil
        clearLocalCopyConfirmation()
        guard let hit = hits.first(where: { $0.id == id }) else {
            cancelOperation()
            error = nil
            return
        }
        let ticket = start(.attachments)
        operation = Task { @MainActor [weak self, attachmentSources] in
            do {
                let sources = try await attachmentSources(hit)
                try Task.checkCancellation()
                guard let self, self.generation == ticket, self.selectedHitID == hit.id else { return }
                self.sources = sources
                self.finish(ticket)
                if sources.count == 1 { self.selectAttachment(sources[0].id) }
            } catch {
                self?.fail(error, ticket: ticket)
            }
        }
    }

    func selectAttachment(_ id: String?) {
        guard isPresented, !completed, phase != .importing else { return }
        cancelOperation()
        selectedAttachmentID = id
        clearLocalCopyConfirmation()
        error = nil
        guard let selectedSource, case .localCopy(let observation) = selectedSource else { return }
        let ticket = start(.resolvingLocalCopy)
        operation = Task { @MainActor [weak self, resolveLocalCopy] in
            do {
                let candidate = try await resolveLocalCopy(observation)
                try Task.checkCancellation()
                guard candidate.observation == observation else { throw ZoteroPDFImportError.invalidResponse }
                guard let self, self.generation == ticket, self.selectedAttachmentID == id else { return }
                self.localCopyCandidate = candidate
                self.finish(ticket)
            } catch {
                self?.fail(error, ticket: ticket)
            }
        }
    }

    func retryLocalCopy() {
        guard canRetryLocalCopy else { return }
        selectAttachment(selectedAttachmentID)
    }

    func importSelection() {
        guard canImport, let option = selectedSource else { return }
        let localCandidate = localCopyCandidate
        let ticket = start(.importing)
        operation = Task { @MainActor [weak self, resolveSource, importPDF, importLocalCopy] in
            do {
                switch option {
                case .verifiedSource(let source):
                    let candidate = try await resolveSource(source)
                    try Task.checkCancellation()
                    guard let self, self.generation == ticket, self.selectedSource?.id == option.id else { return }
                    try await importPDF(candidate)
                case .localCopy(let observation):
                    guard let candidate = localCandidate, candidate.observation == observation,
                        let self, self.generation == ticket, self.selectedSource?.id == option.id,
                        self.localCopyAcknowledged
                    else { return }
                    try Task.checkCancellation()
                    try await importLocalCopy(candidate)
                }
                try Task.checkCancellation()
                guard let self, self.generation == ticket else { return }
                self.completed = true
                self.finish(ticket)
            } catch {
                self?.fail(error, ticket: ticket)
            }
        }
    }

    @discardableResult
    func cancel() -> Bool {
        guard isPresented, !completed, phase != .importing else { return false }
        invalidatePresentation()
        return true
    }

    /// Presentation teardown invalidates late callbacks. It cannot roll back a
    /// final import or an independently dispatched Note binding transaction.
    func invalidatePresentation() {
        isPresented = false
        cancelOperation()
        clearLocalCopyConfirmation()
    }

    private func cancelOperation() {
        generation &+= 1
        operation?.cancel()
        operation = nil
        phase = nil
    }

    private func start(_ phase: Phase) -> UInt64 {
        cancelOperation()
        self.phase = phase
        error = nil
        return generation
    }

    private func finish(_ ticket: UInt64) {
        guard generation == ticket else { return }
        operation = nil
        phase = nil
    }

    private func fail(_ failure: Error, ticket: UInt64) {
        guard generation == ticket else { return }
        clearLocalCopyConfirmation()
        if !(failure is CancellationError) { error = Self.message(failure) }
        finish(ticket)
    }

    private func clearLocalCopyConfirmation() {
        localCopyCandidate = nil
        localCopyAcknowledged = false
    }

    private static func message(_ error: Error) -> String {
        guard let error = error as? ZoteroPDFImportError else { return ScholiumErrorLocalization.message(error) }
        switch error {
        case .importUnavailable:
            return ScholiumL10n.string("PDF import is unavailable through this Zotero connection.")
        case .invalidResponse:
            return ScholiumL10n.string("Zotero returned a PDF attachment Scholium could not verify. Refresh and choose the attachment again.")
        case .stableIdentityUnavailable:
            return ScholiumL10n.string(
                "Scholium could not verify this Zotero connection's database identity. Check the connection and search again, or choose the PDF file directly.")
        case .sourceChanged:
            return ScholiumL10n.string("The Zotero item or attachment changed. Search again before importing its PDF.")
        case .tooManyAttachments:
            return ScholiumL10n.string("This Zotero item has too many attachments to select safely. Choose its PDF from Finder instead.")
        case .originalUnavailable:
            return ScholiumL10n.string("Zotero did not provide a local PDF file. Open the attachment in Zotero, download it if needed, and try again.")
        }
    }
}
