import AppKit
import QuickLook
import QuickLookThumbnailing
import ScholiumContracts
import SwiftUI

/// Uses the retained document projection and the existing bounded preview lease.
struct ResearchAttachmentContext {
    let session: DocumentSessionModel
    let prepare: (UUID) async throws -> DocumentAttachmentPreviewLease
    let release: (UUID) async -> Void
    let refresh: () async throws -> Void
    let attach: (DocumentAttachmentSelectionMode, ScholiumFileSelectionPresenter?) async throws -> Void
}

struct OverviewAttachmentsView: View {
    let context: ResearchAttachmentContext
    @ObservedObject private var session: DocumentSessionModel
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @StateObject private var quickLook = DocumentAttachmentQuickLookSession()
    @State private var selectedID: UUID?
    @State private var expanded = true
    @State private var thumbnail: NSImage?
    @State private var error: String?
    @State private var visible = false
    @State private var loading = false
    @State private var retry = 0
    @State private var previewRequestID = UUID()

    init(context: ResearchAttachmentContext) {
        self.context = context
        _session = ObservedObject(wrappedValue: context.session)
    }
    private var items: [DocumentAttachmentSnapshot] { session.documentAttachments }
    private var index: Int { items.firstIndex { $0.record.id == selectedID } ?? 0 }
    private var selected: DocumentAttachmentSnapshot? { items.indices.contains(index) ? items[index] : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Attachments", systemImage: "paperclip").font(ScholiumTypography.interface(.rowTitle))
                Spacer()
                Menu {
                    Button("Attach a Copy…") { attach(.copyIntoTriptych) }
                    Button("Reference Original…") { attach(.referenceOriginal) }
                } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(session.isAttachingDocument)
                .accessibilityLabel("Add Document")
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                    .accessibilityLabel(expanded ? "Collapse Attachments" : "Expand Attachments")
            }.buttonStyle(.borderless)
            if expanded {
                if session.documentAttachmentsLoading { ProgressView().controlSize(.small) }
                if let problem = session.documentAttachmentsError {
                    Text(problem).font(ScholiumTypography.interface(.body)).foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                    Button("Retry") { Task { try? await context.refresh() } }.buttonStyle(.borderless)
                }
                if let error { Text(error).font(ScholiumTypography.interface(.body)).foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color).textSelection(.enabled) }
                if let item = selected {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Button(item.record.filename) { open(item) }
                            .font(ScholiumTypography.interface(.control)).lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(item.record.filename)
                            .accessibilityIdentifier("scholium.overview.attachment.open")
                        if items.count > 1 {
                            Menu {
                                ForEach(items, id: \.record.id) { attachment in
                                    Button(attachment.record.filename) { selectedID = attachment.record.id }
                                }
                            } label: {
                                Text("\(index + 1) of \(items.count)")
                            }
                            .font(ScholiumTypography.interface(.body)).menuStyle(.borderlessButton).fixedSize()
                            .accessibilityLabel("Choose Attachment")
                            .accessibilityValue(Text("Attachment \(index + 1) of \(items.count)"))
                            .accessibilityIdentifier("scholium.overview.attachment.selection")
                        }
                    }.buttonStyle(.borderless)
                    preview(item)
                } else if !session.documentAttachmentsLoading && session.documentAttachmentsError == nil {
                    Text("No Attachments").font(ScholiumTypography.interface(.body)).foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                }
            }
        }
        .padding(.top, 20)
        .accessibilityIdentifier("scholium.overview.attachments")
        .task(id: "\(selected?.record.id.uuidString ?? ""):\(selected?.availability.rawValue ?? ""):\(expanded):\(retry)") {
            let requestID = UUID()
            previewRequestID = requestID
            loading = false; thumbnail = nil; error = nil
            guard expanded, let item = selected, item.availability == .available else { return }
            loading = true
            defer { if previewRequestID == requestID { loading = false } }
            do {
                let lease = try await context.prepare(item.record.id)
                do {
                    let request = QLThumbnailGenerator.Request(fileAt: lease.fileURL,
                        size: NSSize(width: 760, height: 1000), scale: 1, representationTypes: .thumbnail)
                    let image = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                    if !Task.isCancelled, previewRequestID == requestID { thumbnail = image.nsImage }
                } catch {
                    if !Task.isCancelled, previewRequestID == requestID { self.error = error.localizedDescription }
                }
                await context.release(lease.accessToken)
            } catch {
                if !Task.isCancelled, previewRequestID == requestID { self.error = error.localizedDescription }
            }
        }
        .onChange(of: error ?? session.documentAttachmentsError) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .quickLookPreview(Binding(
            get: { quickLook.url },
            set: { if $0 == nil { quickLook.dismiss() } }
        ))
        .onAppear { visible = true }
        .onDisappear { visible = false; quickLook.dismiss() }
    }

    @ViewBuilder private func preview(_ item: DocumentAttachmentSnapshot) -> some View {
        if let thumbnail {
            Button { open(item) } label: {
                Image(nsImage: thumbnail).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.borderless).accessibilityLabel(Text("Preview \(item.record.filename)"))
                .help(String(localized: "Quick Look"))
        } else {
            VStack(spacing: 8) {
                if loading { ProgressView().controlSize(.small) }
                else {
                    Text(item.availability == .unavailable ? "Attachment Unavailable" : "Preview Unavailable")
                        .font(ScholiumTypography.interface(.body)).foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                    HStack {
                        Button("Retry") { Task {
                            do { try await context.refresh(); retry += 1 }
                            catch { self.error = error.localizedDescription }
                        } }
                        if item.availability == .available { Button("Quick Look") { open(item) } }
                    }.buttonStyle(.borderless)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(0.773, contentMode: .fit)
        }
    }
    private func attach(_ mode: DocumentAttachmentSelectionMode) {
        expanded = true
        Task { @MainActor in
            do { try await context.attach(mode, fileSelectionPresenter) }
            catch is CancellationError { return }
            catch { self.error = error.localizedDescription }
        }
    }
    private func open(_ item: DocumentAttachmentSnapshot) {
        Task { @MainActor in
            do {
                let lease = try await context.prepare(item.record.id)
                guard visible, selected?.record.id == item.record.id else {
                    await context.release(lease.accessToken); return
                }
                quickLook.present(lease, releaseAccess: context.release)
            } catch { self.error = error.localizedDescription }
        }
    }
}
