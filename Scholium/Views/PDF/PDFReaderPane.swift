import AppKit
import ScholiumContracts
import SwiftUI

struct PDFReaderPane: View {
    @ObservedObject var controller: PDFReaderController
    @State private var confirmsReload = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if controller.document != nil {
                    PDFReaderNativeView(controller: controller)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        if controller.isLoading {
                            ProgressView("Opening PDF…")
                        } else if let binding = controller.context?.authoredPath {
                            Image(systemName: "doc.badge.ellipsis").font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
                            Text("PDF Unavailable").font(.headline)
                            if !binding.isEmpty {
                                Text(verbatim: binding).font(.callout).textSelection(.enabled)
                                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("scholium.pdf.unavailable.binding")
                            }
                            Text("The note still points to this PDF. Restore the file and retry, choose a replacement, or detach the binding.")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Replace PDF…") { controller.requestAttachPDF() }.disabled(!controller.canAttach)
                                .accessibilityIdentifier("scholium.pdf.unavailable.replace")
                            Button("Detach PDF") {
                                Task {
                                    do { try await controller.detachPDF() } catch { controller.presentFailure(error) }
                                }
                            }.disabled(!controller.canAttach)
                                .accessibilityIdentifier("scholium.pdf.unavailable.detach")
                        } else {
                            Image(systemName: "doc.richtext").font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
                            Text("PDF Reader").font(.headline)
                            Text("Attach a PDF to this note to read and annotate a shared copy.")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Attach PDF…") { controller.requestAttachPDF() }.disabled(!controller.canAttach)
                                .accessibilityIdentifier("scholium.pdf.attach")
                        }
                    }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if controller.document?.allowsCommenting == false {
                Text("This PDF permits reading only.").font(.caption).foregroundStyle(.secondary)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = controller.error {
                VStack(alignment: .leading, spacing: 8) {
                    if let pending = controller.pendingSaveFilename {
                        Text(verbatim: pending).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(verbatim: error).font(.callout).textSelection(.enabled)
                        .accessibilityIdentifier("scholium.pdf.error")
                    VStack(alignment: .leading, spacing: 6) {
                        if controller.hasUnsavedAnnotations {
                            Button("Retry Save") { controller.retrySave() }.disabled(controller.isSaving)
                            Button("Export Annotations…") { controller.requestExport() }
                            if controller.exportedUnsavedAnnotations {
                                Button("Reload PDF…") { confirmsReload = true }
                            }
                        } else {
                            Button("Retry PDF") { Task { await controller.reload() } }
                                .accessibilityIdentifier("scholium.pdf.retry")
                                .disabled(!controller.canUseReaderCommands || controller.isLoading)
                        }
                    }.controlSize(.small)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            if !controller.recoveryCandidates.isEmpty {
                HStack {
                    Text("An interrupted save has a recovery copy.").font(.callout)
                    Spacer()
                    Menu("Export Recovery…") {
                        ForEach(controller.recoveryCandidates, id: \.id) { recovery in
                            Button(recovery.createdAt.formatted(date: .abbreviated, time: .shortened)) {
                                controller.requestExport(recovery: recovery)
                            }
                        }
                    }
                }.padding(10)
                Divider()
            }
            if controller.showsAnnotations, controller.document != nil {
                annotationList.frame(maxHeight: 190)
            }
            if controller.isSaving {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Saving PDF annotations…").font(.caption)
                    Spacer()
                }.padding(8)
            }
        }
        .background(.background)
        .background(PDFReaderWindowAnchor(controller: controller).frame(width: 0, height: 0))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("PDF Reader")
        .accessibilityIdentifier("scholium.pdf.pane")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.checkExternalChanges() }
        }
        .sheet(isPresented: $controller.attachRequested) {
            PDFReaderAttachView(controller: controller)
        }
        .sheet(isPresented: showsAnnotationPresentation, onDismiss: closeAnnotationPresentation) {
            if let draft = controller.annotationDraft {
                PDFReaderCommentView(controller: controller, draft: draft)
            } else if let detail = controller.annotationDetail {
                PDFReaderAnnotationDetailView(controller: controller, row: detail)
            }
        }
        .confirmationDialog("Reload the PDF and discard the in-memory annotations? Your exported copy is preserved.", isPresented: $confirmsReload) {
            Button("Reload PDF", role: .destructive) { Task { await controller.reload(discardExportedChanges: true) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var showsAnnotationPresentation: Binding<Bool> {
        Binding(
            get: { controller.annotationDraft != nil || controller.annotationDetail != nil },
            set: { if !$0 { closeAnnotationPresentation() } }
        )
    }

    private func closeAnnotationPresentation() {
        controller.cancelComment()
        controller.closeAnnotationDetail()
    }

    private var annotationList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            Text("Annotations").font(.caption).foregroundStyle(.secondary).padding(8)
            List(controller.annotations) { row in
                Button {
                    controller.showAnnotation(row.annotation)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Page \(row.pageIndex + 1)").monospacedDigit()
                            Text(PDFReaderAnnotations.hasType(row.annotation, .highlight) ? LocalizedStringKey("Highlight") : LocalizedStringKey("PDF Comment"))
                        }.font(.caption).foregroundStyle(.secondary)
                        if PDFReaderAnnotations.hasType(row.annotation, .highlight) {
                            if row.passageText.isEmpty {
                                Text("Selected text unavailable").foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: row.passageText).lineLimit(3)
                            }
                            if !row.text.isEmpty {
                                Text(verbatim: row.text).foregroundStyle(.secondary).lineLimit(2)
                            }
                        } else {
                            Text(verbatim: row.text).lineLimit(3)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Read the full annotation and reveal it in the PDF.")
                .accessibilityIdentifier("scholium.pdf.annotation")
                .accessibilityAction(named: Text("Read Annotation")) { controller.showAnnotation(row.annotation) }
            }.accessibilityLabel("PDF Annotations")
        }
    }
}

private struct PDFReaderAnnotationDetailView: View {
    @ObservedObject var controller: PDFReaderController
    let row: PDFReaderAnnotationRow

    private var isHighlight: Bool { PDFReaderAnnotations.hasType(row.annotation, .highlight) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isHighlight ? LocalizedStringKey("Highlight") : LocalizedStringKey("PDF Comment")).font(.headline).accessibilityAddTraits(.isHeader)
            Text("Page \(row.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isHighlight {
                        Text("Selected Passage").font(.subheadline).foregroundStyle(.secondary)
                        if row.passageText.isEmpty {
                            Text("Selected text unavailable").foregroundStyle(.secondary)
                        } else {
                            Text(verbatim: row.passageText)
                                .accessibilityIdentifier("scholium.pdf.annotation.passage")
                        }
                    }
                    if !row.text.isEmpty {
                        if isHighlight { Text("PDF Comment").font(.subheadline).foregroundStyle(.secondary) }
                        Text(verbatim: row.text).accessibilityIdentifier("scholium.pdf.annotation.contents")
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 150, maxHeight: 400)
            if let status = controller.annotationDetailStatus {
                Text(verbatim: status).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scholium.pdf.annotation.refreshStatus")
            }
            HStack {
                Button("Edit Annotation…") { controller.editAnnotation(row.annotation) }
                    .disabled(!controller.canAnnotate)
                    .accessibilityIdentifier("scholium.pdf.annotation.edit")
                Spacer()
                Button("Close") { controller.closeAnnotationDetail() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("scholium.pdf.annotation.close")
            }
        }
        .padding(20)
        .frame(minWidth: 340, idealWidth: 440, maxWidth: 620)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.pdf.annotation.detail")
    }
}

private struct PDFReaderCommentView: View {
    @ObservedObject var controller: PDFReaderController
    let draft: PDFReaderAnnotationDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PDF Comment").font(.headline)
            TextEditor(text: $controller.annotationText).frame(minWidth: 340, minHeight: 150)
                .accessibilityLabel("PDF Comment").accessibilityIdentifier("scholium.pdf.comment")
            if let error = controller.annotationDraftError {
                Text(verbatim: error).font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scholium.pdf.comment.error")
            }
            HStack {
                if draft.annotation != nil {
                    Button("Delete Annotation", role: .destructive) { controller.deleteAnnotation(draft) }
                        .disabled(!controller.canCommitDraft)
                }
                Spacer()
                Button("Cancel") { controller.cancelComment() }.keyboardShortcut(.cancelAction)
                Button("Save Comment") { controller.commitComment(draft, text: controller.annotationText) }
                    .keyboardShortcut(.defaultAction).disabled(!controller.canCommitDraft)
                    .accessibilityIdentifier("scholium.pdf.comment.save")
            }
        }.padding(20).interactiveDismissDisabled()
    }
}

private struct PDFReaderWindowAnchor: NSViewRepresentable {
    let controller: PDFReaderController
    func makeNSView(context: Context) -> AnchorView { AnchorView(controller: controller) }
    func updateNSView(_ view: AnchorView, context: Context) {}
    static func dismantleNSView(_ view: AnchorView, coordinator: ()) { view.invalidate() }

    final class AnchorView: NSView {
        private weak var controller: PDFReaderController?
        private weak var registeredWindow: NSWindow?
        init(controller: PDFReaderController) {
            self.controller = controller
            super.init(frame: .zero)
            setAccessibilityElement(false)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let registeredWindow { controller?.unregisterPresentationWindow(registeredWindow) }
            registeredWindow = window
            if let window { controller?.registerPresentationWindow(window) }
        }
        func invalidate() {
            if let registeredWindow { controller?.unregisterPresentationWindow(registeredWindow) }
            controller = nil
        }
    }
}
