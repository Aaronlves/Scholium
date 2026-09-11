import ScholiumContracts
import SwiftUI

struct AgentChatPDFPagesView: View {
    struct Target: Identifiable {
        var id: UUID { material.id }
        let material: AgentChatLocalMaterial
        let conversationID: UUID
    }
    @ObservedObject var controller: AgentChatController
    let target: Target
    @Environment(\.dismiss) private var dismiss
    @State private var pageCount: Int?
    @State private var selection = ""
    @State private var error: String?
    @State private var operation: Task<Void, Never>?

    var body: some View {
        AgentChatPDFPagesForm(
            fileName: target.material.fileName, pageCount: pageCount, selection: $selection,
            error: error, isPreparing: operation != nil,
            canUse: !controller.preparingMaterials.contains(target.conversationID),
            use: prepare,
            cancel: {
                operation?.cancel()
                dismiss()
            }
        )
        .task {
            do {
                let count = try await controller.pdfPageCount(for: target.material)
                guard !Task.isCancelled else { return }
                pageCount = count
            } catch {
                guard !Task.isCancelled else { return }
                self.error = AgentChatLocalMaterialLabels.error(error)
            }
        }
        .onDisappear { operation?.cancel() }
    }

    private func prepare() {
        operation = Task { @MainActor in
            defer { operation = nil }
            error = nil
            let succeeded = await controller.usePDFPages(selection, from: target.material, in: target.conversationID)
            guard !Task.isCancelled else { return }
            if succeeded {
                dismiss()
            } else {
                error =
                    controller.materialErrors[target.conversationID]
                    ?? String(localized: "The PDF pages could not be prepared. The previous material is retained.")
            }
        }
    }

}

struct AgentChatPDFPagesForm: View {
    let fileName: String
    let pageCount: Int?
    @Binding var selection: String
    let error: String?
    let isPreparing: Bool
    let canUse: Bool
    let use: () -> Void
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Use Page Images").font(.headline).accessibilityAddTraits(.isHeader)
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text(fileName).lineLimit(2)
                    if let pageCount {
                        Text("\(pageCount) Pages")
                        TextField("Pages", text: $selection, prompt: Text("1–5, 8"))
                            .disabled(isPreparing)
                        Text("Physical page numbers · Up to 20 pages").font(.caption).foregroundStyle(.secondary)
                    } else if error == nil {
                        if reduceMotion { Text("Reading PDF", bundle: .module) } else { ProgressView("Reading PDF") }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                if isPreparing {
                    if reduceMotion {
                        Text("Preparing Page Images", bundle: .module)
                    } else {
                        ProgressView().controlSize(.small).accessibilityLabel("Preparing Page Images")
                    }
                }
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Use Pages", action: use).keyboardShortcut(.defaultAction)
                    .disabled(
                        pageCount == nil || isPreparing || !canUse
                            || selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 400, alignment: .leading).tint(nil as Color?)
    }
}
