import Foundation
import ImageIO
import PDFKit
import ScholiumContracts
import UniformTypeIdentifiers

/// Owns immutable machine-local file copies. It never writes the selected source.
public actor AgentChatMaterialStore {
  private let root: URL
  private static let maximumFileBytes = 20 * 1_024 * 1_024
  private static let maximumTextBytes = 1_024 * 1_024
  public init(root: URL) { self.root = root }

  public func stage(_ source: URL) throws -> AgentChatLocalMaterial {
    try Task.checkCancellation()
    let id = UUID()
    let type = UTType(filenameExtension: source.pathExtension)
    let kind: AgentChatLocalMaterial.Kind = type == .pdf ? .pdf :
      (type?.conforms(to: .image) == true ? .image :
        (type?.conforms(to: .text) == true || source.pathExtension.lowercased() == "md" ? .text : .unsupported))
    var data: Data?
    var failure: AgentChatLocalMaterial.Issue?
    let access = source.startAccessingSecurityScopedResource()
    defer { if access { source.stopAccessingSecurityScopedResource() } }
    do {
      guard source.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
      let coordinator = NSFileCoordinator()
      var coordinationError: NSError?
      coordinator.coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { location in
        do {
          let before = try location.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
          guard before.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
          guard (before.fileSize ?? Int.max) <= Self.maximumFileBytes else { failure = .tooLarge; return }
          let handle = try FileHandle(forReadingFrom: location)
          defer { try? handle.close() }
          var bytes = Data()
          while bytes.count <= Self.maximumFileBytes {
            guard let chunk = try handle.read(upToCount: min(64 * 1_024, Self.maximumFileBytes + 1 - bytes.count)), !chunk.isEmpty else { break }
            bytes.append(chunk)
          }
          guard bytes.count <= Self.maximumFileBytes else { failure = .tooLarge; return }
          var refreshed = URL(fileURLWithPath: location.path)
          refreshed.removeAllCachedResourceValues()
          let after = try refreshed.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
          guard before.fileSize == after.fileSize, before.contentModificationDate == after.contentModificationDate,
            bytes.count == before.fileSize else { failure = .unreadable; return }
          data = bytes
        } catch { failure = .unreadable }
      }
      if coordinationError != nil { failure = .unreadable }
    } catch { failure = .unreadable }
    try Task.checkCancellation()
    guard let data, failure == nil else {
      return .init(id: id, source: .file(source), storedFileName: nil, fingerprint: nil, kind: kind, issue: failure ?? .unreadable)
    }
    try prepare()
    let suffix = type?.preferredFilenameExtension ?? "data"
    let name = id.uuidString + "." + suffix
    let destination = root.appendingPathComponent(name)
    try data.write(to: destination, options: .withoutOverwriting)
    try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: destination.path)
    var text = ""
    var pages: [AgentChatLocalMaterial.Page] = []
    var issue: AgentChatLocalMaterial.Issue?
    switch kind {
    case .text:
      if data.count > Self.maximumTextBytes { issue = .tooLarge }
      else if let decoded = String(validating: data, as: UTF8.self) { text = decoded }
      else { issue = .unreadable }
    case .pdf:
      if let pdf = PDFDocument(data: data) {
        if pdf.isLocked { issue = .locked }
        else if pdf.pageCount > 2_000 { issue = .tooLarge }
        else {
          var total = 0
          for index in 0..<pdf.pageCount {
            if Task.isCancelled { break }
            let value = pdf.page(at: index)?.string ?? ""
            total += value.utf8.count
            if total > Self.maximumTextBytes { issue = .tooLarge; pages = []; break }
            pages.append(.init(number: index + 1, text: value))
          }
          if issue == nil && pages.allSatisfy({ $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { issue = .noText }
        }
      } else { issue = .unreadable }
    case .image:
      issue = Self.imageIssue(data)
    case .unsupported: issue = .unsupported
    }
    if Task.isCancelled { try? FileManager.default.removeItem(at: destination); throw CancellationError() }
    return .init(id: id, source: .file(source), storedFileName: name, fingerprint: .init(data: data),
      kind: kind, text: text, pages: pages, issue: issue)
  }

  public func stageImageCapture(_ data: Data, origin: AgentChatLocalMaterial.CaptureOrigin) throws -> AgentChatLocalMaterial {
    try Task.checkCancellation()
    let id = UUID()
    guard data.count <= Self.maximumFileBytes else {
      return .init(id: id, source: .imageCapture(origin), storedFileName: nil, fingerprint: nil, kind: .image, issue: .tooLarge)
    }
    try prepare()
    let source = CGImageSourceCreateWithData(data as CFData, nil)
    let type = source.flatMap(CGImageSourceGetType).flatMap { UTType($0 as String) }
    let capturedName = id.uuidString + "." + (type?.preferredFilenameExtension ?? "data")
    let capturedURL = root.appendingPathComponent(capturedName)
    try data.write(to: capturedURL, options: .withoutOverwriting)
    var created = [capturedURL]
    do {
      try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: capturedURL.path)
      let issue = Self.imageIssue(data, allowsTIFF: true)
      guard issue == nil, type == .tiff, let source else {
        try Task.checkCancellation()
        return .init(id: id, source: .imageCapture(origin), storedFileName: capturedName, fingerprint: .init(data: data), kind: .image, issue: issue)
      }
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
      guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        kCGImageSourceShouldCache: false
      ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
      let png = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
      CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
      guard CGImageDestinationFinalize(destination), png.length <= Self.maximumFileBytes else { throw CocoaError(.fileWriteOutOfSpace) }
      try Task.checkCancellation()
      let name = id.uuidString + ".png"
      let url = root.appendingPathComponent(name)
      try (png as Data).write(to: url, options: .withoutOverwriting)
      created.append(url)
      try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
      return .init(id: id, source: .imageCapture(origin), storedFileName: name, fingerprint: .init(data: png as Data), kind: .image,
        capturedFileName: capturedName, capturedFingerprint: .init(data: data))
    } catch is CancellationError {
      for url in created { try? FileManager.default.removeItem(at: url) }
      throw CancellationError()
    } catch {
      for url in created.dropFirst() { try? FileManager.default.removeItem(at: url) }
      return .init(id: id, source: .imageCapture(origin), storedFileName: capturedName, fingerprint: .init(data: data), kind: .image, issue: .unreadable)
    }
  }

  private static func imageIssue(_ data: Data, allowsTIFF: Bool = false) -> AgentChatLocalMaterial.Issue? {
    guard let image = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(image) == 1,
      let rawType = CGImageSourceGetType(image), let actual = UTType(rawType as String),
      ([UTType.png, .jpeg, .webP, .gif].contains(actual) || (allowsTIFF && actual == .tiff)) else { return .unsupported }
    guard let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
      width.doubleValue > 0, height.doubleValue > 0,
      width.doubleValue * height.doubleValue <= 40_000_000 else { return .tooLarge }
    return CGImageSourceCreateImageAtIndex(image, 0, [kCGImageSourceShouldCache: false] as CFDictionary) == nil ? .unreadable : nil
  }

  public func validatedURL(for material: AgentChatLocalMaterial) throws -> URL {
    try prepare()
    guard let name = material.storedFileName, let fingerprint = material.fingerprint else { throw CocoaError(.fileReadCorruptFile) }
    if let captured = material.capturedFileName, let fingerprint = material.capturedFingerprint {
      _ = try readSnapshot(name: captured, id: material.id, fingerprint: fingerprint)
    } else if material.capturedFileName != nil || material.capturedFingerprint != nil { throw CocoaError(.fileReadCorruptFile) }
    return try readSnapshot(name: name, id: material.id, fingerprint: fingerprint).url
  }

  private func readSnapshot(name: String, id: UUID, fingerprint: DocumentFingerprint) throws -> (url: URL, data: Data) {
    guard name == URL(fileURLWithPath: name).lastPathComponent, name.hasPrefix(id.uuidString + ".")
    else { throw CocoaError(.fileReadCorruptFile) }
    let url = root.appendingPathComponent(name)
    let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
      (attributes.fileSize ?? Int.max) <= Self.maximumFileBytes else { throw CocoaError(.fileReadCorruptFile) }
    let data = try Data(contentsOf: url)
    guard data.count <= Self.maximumFileBytes, DocumentFingerprint(data: data) == fingerprint
    else { throw CocoaError(.fileReadCorruptFile) }
    return (url, data)
  }

  public func pdfPageCount(for material: AgentChatLocalMaterial) throws -> Int {
    try pdfSnapshot(material).document.pageCount
  }

  private func pdfSnapshot(_ material: AgentChatLocalMaterial) throws -> (document: PDFDocument, data: Data) {
    try prepare()
    guard material.kind == .pdf, let name = material.storedFileName, let fingerprint = material.fingerprint else {
      throw AgentChatPDFPageSelectionFailure.unavailable
    }
    let data = try readSnapshot(name: name, id: material.id, fingerprint: fingerprint).data
    guard let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else {
      throw AgentChatPDFPageSelectionFailure.unavailable
    }
    return (document, data)
  }

  public func renderPDFPages(_ selection: String, from material: AgentChatLocalMaterial) throws -> AgentChatLocalMaterial {
    try Task.checkCancellation()
    let snapshot = try pdfSnapshot(material)
    let numbers = try AgentChatPDFPageSelection.parse(selection, pageCount: snapshot.document.pageCount)
    let id = UUID()
    let sourceName = id.uuidString + ".pdf"
    var created: [URL] = []
    do {
      let source = root.appendingPathComponent(sourceName)
      try snapshot.data.write(to: source, options: .withoutOverwriting)
      created.append(source)
      try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: source.path)
      var images: [AgentChatLocalMaterial.PageImage] = []
      for number in numbers {
        try Task.checkCancellation()
        let data: Data = try autoreleasepool {
          guard let page = snapshot.document.page(at: number - 1) else { throw CocoaError(.fileReadCorruptFile) }
          let bounds = page.bounds(for: .cropBox)
          guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
          }
          let image = page.thumbnail(of: CGSize(width: 2_400, height: 2_400), for: .cropBox)
          guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw CocoaError(.fileReadCorruptFile) }
          let data = NSMutableData()
          guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
          }
          CGImageDestinationAddImage(destination, cgImage, nil)
          guard CGImageDestinationFinalize(destination), data.length <= Self.maximumFileBytes else { throw CocoaError(.fileWriteOutOfSpace) }
          return data as Data
        }
        let name = id.uuidString + ".page-\(number).png"
        let url = root.appendingPathComponent(name)
        try data.write(to: url, options: .withoutOverwriting)
        created.append(url)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
        images.append(.init(number: number, storedFileName: name, fingerprint: .init(data: data)))
      }
      try Task.checkCancellation()
      return .init(id: id, source: material.source, storedFileName: sourceName,
        fingerprint: .init(data: snapshot.data), kind: .pdf, pageImages: images)
    } catch {
      for url in created { try? FileManager.default.removeItem(at: url) }
      throw error
    }
  }

  public func validatedPageImageURLs(for material: AgentChatLocalMaterial) throws -> [URL] {
    try prepare()
    guard material.kind == .pdf, material.pageImages.count <= AgentChatPDFPageSelection.maximumPages,
      Set(material.pageImages.map(\.number)).count == material.pageImages.count else { throw CocoaError(.fileReadCorruptFile) }
    return try material.pageImages.map { page in
      guard page.number > 0, page.storedFileName == material.id.uuidString + ".page-\(page.number).png" else { throw CocoaError(.fileReadCorruptFile) }
      return try readSnapshot(name: page.storedFileName, id: material.id, fingerprint: page.fingerprint).url
    }
  }

  /// Caller has confirmed that no retained draft or message references this copy.
  public func discard(_ material: AgentChatLocalMaterial) throws {
    try prepare()
    guard let name = material.storedFileName else { return }
    guard name == URL(fileURLWithPath: name).lastPathComponent, name.hasPrefix(material.id.uuidString + ".")
    else { throw CocoaError(.fileWriteInvalidFileName) }
    var names = [name]
    if let captured = material.capturedFileName {
      guard captured == URL(fileURLWithPath: captured).lastPathComponent, captured.hasPrefix(material.id.uuidString + ".") else { throw CocoaError(.fileWriteInvalidFileName) }
      names.append(captured)
    }
    for page in material.pageImages {
      guard page.number > 0, page.storedFileName == material.id.uuidString + ".page-\(page.number).png" else { throw CocoaError(.fileWriteInvalidFileName) }
      names.append(page.storedFileName)
    }
    for name in names {
      let url = root.appendingPathComponent(name)
      if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
  }

  private func prepare() throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileWriteInvalidFileName) }
  }
}
