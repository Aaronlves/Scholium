import QuickLook
import QuickLookThumbnailing
import ScholiumContracts
import SwiftUI

struct AgentChatLocalMaterialChip: View {
  let material: AgentChatLocalMaterial
  let preview: () async throws -> URL
  let remove: (() -> Void)?
  let replace: (() -> Void)?
  var usePages: (() -> Void)? = nil
  @State private var showsDetails = false
  @State private var previewURL: URL?
  @State private var previewError: String?
  @State private var isOpening = false
  @State private var previewTask: Task<Void, Never>?
  @State private var thumbnail: NSImage?

  var body: some View {
    GroupBox {
      HStack(alignment: .top, spacing: 8) {
        Button {
          showsDetails = true
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Label(
              AgentChatLocalMaterialLabels.title(material), systemImage: material.kind == .image ? "photo" : "doc.text"
            )
            .font(.subheadline).lineLimit(1)
            Text(AgentChatLocalMaterialLabels.summary(material)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Preview material: \(AgentChatLocalMaterialLabels.title(material))")
        if let remove {
          Button(action: remove) { Image(systemName: "xmark") }
            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(
              "Remove material: \(AgentChatLocalMaterialLabels.title(material))")
        }
      }
    }
    .frame(width: 200).fixedSize(horizontal: false, vertical: true)
    .popover(isPresented: $showsDetails) {
      AgentChatLocalMaterialDetails(
        material: material, isOpening: isOpening, previewError: previewError, thumbnail: thumbnail,
        open: openPreview,
        replace: replace.map { action in
          {
            showsDetails = false
            action()
          }
        },
        usePages: usePages.map { action in
          {
            showsDetails = false
            action()
          }
        })
    }
    .quickLookPreview($previewURL)
    .onDisappear {
      previewTask?.cancel()
      previewURL = nil
    }
    .task(id: showsDetails) {
      guard showsDetails, material.kind == .image, material.issue == nil, thumbnail == nil else { return }
      do {
        let url = try await preview()
        let request = QLThumbnailGenerator.Request(
          fileAt: url, size: NSSize(width: 640, height: 400), scale: 1, representationTypes: .thumbnail)
        let result = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        guard !Task.isCancelled else { return }
        thumbnail = result.nsImage
      } catch {
        guard !Task.isCancelled else { return }
        previewError = String(localized: "Image preview is unavailable. Try Quick Look.")
      }
    }
  }

  private func openPreview() {
    isOpening = true
    previewError = nil
    previewTask = Task { @MainActor in
      defer {
        isOpening = false
        previewTask = nil
      }
      do {
        let url = try await preview()
        guard !Task.isCancelled else { return }
        previewURL = url
      } catch {
        guard !Task.isCancelled else { return }
        previewError = String(localized: "The retained file is unavailable. Replace it to capture a new snapshot.")
      }
    }
  }

}

struct AgentChatLocalMaterialDetails: View {
  let material: AgentChatLocalMaterial
  let isOpening: Bool
  let previewError: String?
  var thumbnail: NSImage? = nil
  let open: () -> Void
  let replace: (() -> Void)?
  var usePages: (() -> Void)? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(AgentChatLocalMaterialLabels.title(material)).font(.headline).textSelection(.enabled)
      GroupBox {
        VStack(alignment: .leading, spacing: 6) {
          Text(AgentChatLocalMaterialLabels.summary(material)).font(.callout)
          switch material.source {
          case .file(let url):
            Text(url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
          case .imageCapture(.clipboard):
            Text("Clipboard").font(.caption).foregroundStyle(.secondary)
          case .imageCapture(.drop):
            Text("Drag and Drop").font(.caption).foregroundStyle(.secondary)
          }
          if material.capturedFileName != nil {
            Text("Converted to PNG").font(.caption).foregroundStyle(.secondary)
          }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
      }
      if let thumbnail {
        Image(nsImage: thumbnail).resizable().scaledToFit().frame(maxHeight: 200)
          .accessibilityLabel(AgentChatLocalMaterialLabels.title(material))
      }
      if material.issue == .tooLarge {
        Text("Up to 20 MB per file, 1 MB of text, or 40 million image pixels.").font(.caption).foregroundStyle(
          .secondary)
      } else if material.issue == .noText {
        Text("Add page images or choose a PDF with selectable text.").font(.caption).foregroundStyle(.secondary)
      } else if material.issue == .unsupported {
        Text("Use UTF-8 text, a PDF, or a single PNG, JPEG, WebP or GIF image.").font(.caption).foregroundStyle(
          .secondary)
      }
      if !material.pagesWithoutText.isEmpty {
        Text("Pages without extracted text: \(AgentChatLocalMaterialLabels.pageRanges(material.pagesWithoutText))")
          .font(.caption).foregroundStyle(.secondary)
      }
      if !material.pageImages.isEmpty {
        Text("Page images: \(AgentChatLocalMaterialLabels.pageRanges(material.pageImages.map(\.number)))")
          .font(.caption).foregroundStyle(.secondary)
      }
      if !material.text.isEmpty || !material.pages.isEmpty {
        GroupBox {
          ScrollView {
            VStack(alignment: .leading, spacing: 12) {
              if !material.text.isEmpty { Text(material.text).textSelection(.enabled) }
              ForEach(material.pages, id: \.number) { page in
                Text("Page \(page.number)").font(.headline)
                Text(page.text).textSelection(.enabled)
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }.frame(maxHeight: 280).padding(4)
        }
      }
      if let previewError { Text(previewError).font(.callout).foregroundStyle(.secondary) }
      HStack {
        Button("Quick Look", action: open).disabled(isOpening || material.storedFileName == nil)
        if let replace { Button("Replace File…", action: replace) }
      }
      if let usePages, material.kind == .pdf, material.storedFileName != nil {
        Button("Use Page Images…", action: usePages)
      }
    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).frame(width: 360).tint(nil as Color?)
  }
}
