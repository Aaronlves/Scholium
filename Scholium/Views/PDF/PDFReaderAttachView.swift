import Foundation
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

struct PDFReaderAttachView: View {
    @ObservedObject var controller: PDFReaderController
    @Environment(\.dismiss) private var dismiss
    @State private var records: [PortableAttachmentRecord] = []
    @State private var selectedID: UUID?
    @State private var choosesFile = false
    @State private var choosesZotero = false
    @State private var importsNewVersion = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var isWorking = false
    @State private var showsDetails = false
    @State private var isPresented = true
    @State private var presentedContext: PDFReaderNoteContext?

    init(controller: PDFReaderController) {
        _controller = ObservedObject(wrappedValue: controller)
        _presentedContext = State(initialValue: controller.context)
    }

    private var choices: [PDFReaderAttachmentChoice] {
        PDFReaderAttachmentChoice.choices(records: records, currentID: controller.currentAttachmentID)
    }

    private var selectedChoice: PDFReaderAttachmentChoice? { choices.first { $0.id == selectedID } }

    var body: some View {
        Group {
            if choosesZotero, let zotero = controller.zotero {
                ZoteroPDFImportView(
                    search: { try await zotero.searchLibrary(query: $0) },
                    attachments: { try await zotero.pdfImportOptions(for: $0) },
                    resolve: { try await zotero.resolvePDFImport($0) },
                    importPDF: { candidate in
                        try requirePresentationContext()
                        try await controller.importPDF(at: candidate.originalURL, zoteroSource: candidate.source, allowNewVersion: importsNewVersion)
                        dismiss()
                    },
                    resolveLocalCopy: { try await zotero.resolvePDFLocalCopy($0) },
                    importLocalCopy: { candidate in
                        try requirePresentationContext()
                        try await controller.importLocalCopy(candidate, allowNewVersion: importsNewVersion)
                        dismiss()
                    },
                    onBack: {
                        guard isPresented else { return }
                        choosesZotero = false
                    },
                    chooseFile: {
                        guard isPresented, controller.context == presentedContext else { return }
                        choosesZotero = false
                        choosesFile = true
                    })
            } else {
                chooser
            }
        }
        .frame(width: choosesZotero ? 560 : 500, height: choosesZotero ? 600 : 480)
        .interactiveDismissDisabled(isWorking || choosesZotero || showsDetails)
        .task {
            do {
                try requirePresentationContext()
                let available = try await controller.availablePDFs()
                try Task.checkCancellation()
                try requirePresentationContext()
                records = available
                selectedID = PDFReaderAttachmentChoice.retainedSelection(selectedID, records: available)
            } catch is CancellationError {} catch {
                guard isPresented, controller.context == presentedContext else { return }
                self.error = PDFReaderPresentationError.message(error)
            }
        }
        .onDisappear {
            isPresented = false
            if !isWorking { task?.cancel() }
        }
        .fileImporter(isPresented: $choosesFile, allowedContentTypes: [.pdf]) { result in
            guard isPresented, !isWorking, controller.context == presentedContext else { return }
            switch result {
            case .success(let url):
                run { try await controller.importPDF(at: url, allowNewVersion: importsNewVersion) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { self.error = PDFReaderPresentationError.message(error) }
            }
        }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attach PDF").font(.headline)
            Text("Choose a shared PDF or import a separate copy. The note's pdf property records its binding; detaching preserves the PDF and annotations.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Choose PDF File…") { choosesFile = true }.accessibilityIdentifier("scholium.pdf.chooseFile")
                Button("Import from Zotero…") { choosesZotero = true }.disabled(controller.zotero == nil)
            }.disabled(isWorking)
            List(selection: $selectedID) {
                ForEach(choices) { choice in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: choice.record.filename).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 6)
                            if let label = choice.copyLabel { Text(verbatim: label).font(.caption).foregroundStyle(.secondary) }
                        }
                        Text(verbatim: choice.summary).font(.caption).foregroundStyle(.secondary)
                        if let source = choice.record.zoteroSource {
                            Text(verbatim: source.item.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        if choice.isCurrent { Text("Currently Attached").font(.caption).foregroundStyle(.secondary) }
                    }
                    .tag(choice.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("scholium.pdf.shared.\(choice.id.uuidString.lowercased())")
                }
            }.overlay {
                if records.isEmpty { Text("No Shared PDFs").foregroundStyle(.secondary) }
            }.disabled(isWorking).accessibilityLabel("Shared PDFs")
            Button("PDF Details") { showsDetails.toggle() }
                .disabled(isWorking || (selectedChoice == nil && controller.context?.authoredPath == nil))
                .accessibilityIdentifier("scholium.pdf.details")
                .popover(isPresented: $showsDetails) {
                    PDFReaderAttachmentDetails(
                        choice: selectedChoice, authoredPath: controller.context?.authoredPath,
                        close: { showsDetails = false })
                }
            Toggle("Create a new PDF copy", isOn: $importsNewVersion)
                .help("A new version preserves the existing copy and its annotations.").disabled(isWorking)
            if let error { Text(verbatim: error).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                    Text("Importing PDF…").font(.callout)
                }
                Spacer()
                Button("Cancel") {
                    guard !isWorking else { return }
                    if showsDetails {
                        showsDetails = false
                        return
                    }
                    isPresented = false
                    task?.cancel()
                    dismiss()
                }.keyboardShortcut(.cancelAction).disabled(isWorking)
                Button("Attach Selected PDF") {
                    guard let selectedID else { return }
                    run { try await controller.attachExisting(selectedID) }
                }.keyboardShortcut(.defaultAction).disabled(selectedID == nil || isWorking)
            }
        }.padding(20)
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard isPresented, !isWorking, controller.context == presentedContext else { return }
        isWorking = true
        error = nil
        task = Task { @MainActor in
            defer { isWorking = false }
            do {
                try requirePresentationContext()
                try await operation()
                try Task.checkCancellation()
                guard isPresented else { return }
                dismiss()
            } catch is CancellationError {} catch {
                guard isPresented else { return }
                self.error = PDFReaderPresentationError.message(error)
            }
        }
    }

    private func requirePresentationContext() throws {
        guard isPresented, controller.context == presentedContext else { throw CancellationError() }
    }
}

/// Presentation-only identity and provenance; selection continues to use the
/// catalog UUID. Copy ordinals distinguish colliding names, not import order.
struct PDFReaderAttachmentChoice: Identifiable {
    let record: PortableAttachmentRecord
    let copyOrdinal: Int?
    let isCurrent: Bool
    var id: UUID { record.id }

    var copyLabel: String? {
        copyOrdinal.map { String(format: ScholiumL10n.string("Copy %lld"), Int64($0)) }
    }

    var originalSize: String? {
        record.importedSourceFingerprint.map { ByteCountFormatter.string(fromByteCount: Int64($0.byteCount), countStyle: .file) }
    }

    var sourceLabel: String {
        if let source = record.zoteroSource { return "Zotero · \(source.library.name)" }
        return ScholiumL10n.string("Imported PDF")
    }

    var summary: String {
        [sourceLabel, originalSize.map { "\(ScholiumL10n.string("Original size")): \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    var storedPath: String {
        switch record.location {
        case .triptychRelative(let path): ".scholium/\(path.rawValue)"
        case .vaultRelative(let path): path.rawValue
        case .external(let reference): reference.filename
        }
    }

    static func choices(records: [PortableAttachmentRecord], currentID: UUID?) -> [Self] {
        let counts = Dictionary(grouping: records, by: \.filename).mapValues(\.count)
        let sorted = records.sorted {
            let comparison = $0.filename.localizedStandardCompare($1.filename)
            return comparison == .orderedSame ? $0.id.uuidString < $1.id.uuidString : comparison == .orderedAscending
        }
        var ordinals: [String: Int] = [:]
        return sorted.map { record in
            ordinals[record.filename, default: 0] += 1
            return Self(
                record: record, copyOrdinal: counts[record.filename, default: 0] > 1 ? ordinals[record.filename] : nil, isCurrent: record.id == currentID)
        }
    }

    static func retainedSelection(_ id: UUID?, records: [PortableAttachmentRecord]) -> UUID? {
        guard let id, records.contains(where: { $0.id == id }) else { return nil }
        return id
    }
}

private struct PDFReaderAttachmentDetails: View {
    let choice: PDFReaderAttachmentChoice?
    let authoredPath: String?
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let choice {
                        Text(verbatim: choice.record.filename).font(.headline)
                        if let label = choice.copyLabel { Text(verbatim: label).foregroundStyle(.secondary) }
                        LabeledContent("Source", value: choice.sourceLabel)
                        if let size = choice.originalSize { LabeledContent("Original size", value: size) }
                        LabeledContent("Storage path") { Text(verbatim: choice.storedPath) }
                        if let fingerprint = choice.record.importedSourceFingerprint {
                            LabeledContent("Original SHA-256") { Text(verbatim: fingerprint.sha256).font(.caption.monospaced()) }
                        }
                        if let source = choice.record.zoteroSource {
                            LabeledContent("Zotero Item") { Text(verbatim: source.item.title) }
                            LabeledContent("Zotero Item Link") { Text(verbatim: source.itemReference.url.absoluteString) }
                            LabeledContent("Zotero Attachment Link") { Text(verbatim: source.pdfReference.url.absoluteString) }
                            LabeledContent("Zotero Database") { Text(verbatim: source.serverID) }
                        }
                    }
                    if let authoredPath {
                        if choice != nil { Divider() }
                        Text("Current binding").font(.headline)
                        Text(verbatim: authoredPath)
                    }
                }
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
            }
            HStack {
                Spacer()
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("scholium.pdf.details.close")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 380, height: 300)
        .accessibilityLabel("PDF Details")
        .onExitCommand(perform: close)
    }
}
