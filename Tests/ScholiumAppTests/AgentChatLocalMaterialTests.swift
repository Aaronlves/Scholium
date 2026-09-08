import AppKit
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing
import PDFKit

@testable import ScholiumApp

@Suite("Local Chat material delivery", .serialized)
@MainActor
struct AgentChatLocalMaterialTests {
  private func wait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !condition() {
      try #require(ContinuousClock.now < deadline, "Local material fixture did not become ready")
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test("Scanned PDF pages replace only the captured draft and send the selected page images")
  func scannedPDFPages() async throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let root = repository.appendingPathComponent(".build/agent-chat-evolution/scanned-pdf-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 30, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    let image = NSImage(size: NSSize(width: 20, height: 30)); image.addRepresentation(bitmap)
    let pdf = PDFDocument()
    pdf.insert(try #require(PDFPage(image: image)), at: 0)
    pdf.insert(try #require(PDFPage(image: image)), at: 1)
    let file = root.appendingPathComponent("scanned.pdf")
    let original = try #require(pdf.dataRepresentation())
    try original.write(to: file)
    let controller = AgentChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await wait { controller.isLoaded }
    let owner = try #require(controller.selectedID)
    controller.editDraft("Discuss the selected page.")
    await controller.addLocalFiles([file], to: owner)
    let old = try #require(controller.selected?.localMaterials.first)
    #expect(old.issue == .noText && controller.materialInputIssue != nil)
    #expect(!(await controller.usePDFPages("3", from: old, in: owner)))
    #expect(controller.selected?.localMaterials == [old])
    let cancelled = Task { await controller.usePDFPages("1", from: old, in: owner) }
    cancelled.cancel()
    #expect(!(await cancelled.value))
    #expect(controller.selected?.localMaterials == [old])
    controller.newConversation()
    let other = controller.selectedID
    #expect(await controller.usePDFPages("2", from: old, in: owner))
    #expect(controller.selectedID == other && controller.selected?.localMaterials.isEmpty == true)
    controller.select(owner)
    let rendered = try #require(controller.selected?.localMaterials.first)
    #expect(rendered.pageImages.map(\.number) == [2] && rendered.pages.isEmpty && rendered.issue == nil)
    #expect(rendered.fingerprint == old.fingerprint && rendered.id != old.id)
    #expect(controller.materialInputIssue != nil)
    let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    controller.connect(executable: fixture, home: controller.runtimeHome, cli: fixture)
    try await wait { controller.canSend }
    controller.send()
    try await wait { !controller.isBusy && controller.selected?.messages.isEmpty == false }
    let turn = try JSONDecoder().decode(MCPJSONValue.self, from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json")))
    let input = try #require(turn.objectValue?["input"]?.arrayValue)
    let images = input.filter { $0.objectValue?["type"]?.stringValue == "localImage" }
    #expect(images.count == 1 && images[0].objectValue?["path"]?.stringValue?.hasSuffix(".page-2.png") == true)
    #expect(input.first?.objectValue?["text"]?.stringValue?.contains("Rendered page images only") == true)
    #expect(input.contains { $0.objectValue?["text"]?.stringValue?.contains("physical page 2") == true })
    #expect(try Data(contentsOf: file) == original)
    await controller.disconnect()
  }

  @Test("Local files persist with their owner; valid images use image input and invalid copies preserve the draft")
  func delivery() async throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let root = repository.appendingPathComponent(".build/agent-chat-evolution/local-chat-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("figure.png")
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    let bytes = try #require(bitmap.representation(using: .png, properties: [:]))
    try bytes.write(to: file)
    let controller = AgentChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await wait { controller.isLoaded }
    let owner = try #require(controller.selectedID)
    controller.editDraft("Discuss this figure.")
    controller.newConversation()
    await controller.addLocalFiles([file], to: owner)
    #expect(controller.selected?.localMaterials.isEmpty == true)
    controller.select(owner)
    let material = try #require(controller.selected?.localMaterials.first)
    #expect(material.kind == .image && material.issue == nil)
    #expect(controller.materialInputIssue != nil)
    let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    controller.connect(executable: fixture, home: controller.runtimeHome, cli: fixture)
    try await wait { controller.canSend }
    controller.send(); controller.stop()
    try await wait { !controller.isBusy }
    #expect(controller.selected?.messages.isEmpty == true && controller.selected?.draft == "Discuss this figure.")
    #expect(controller.selected?.pendingMessageID == nil)
    controller.send()
    try await wait { !controller.isBusy && controller.selected?.pendingMessageID == nil && controller.selected?.messages.isEmpty == false }
    let turn = try JSONDecoder().decode(MCPJSONValue.self, from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json")))
    let image = try #require(turn.objectValue?["input"]?.arrayValue?.first { $0.objectValue?["type"]?.stringValue == "localImage" })
    let sentPath = try #require(image.objectValue?["path"]?.stringValue)
    let sentBytes = try Data(contentsOf: URL(fileURLWithPath: sentPath))
    #expect(sentPath != file.path && sentBytes == bytes)
    #expect(controller.selected?.messages.first?.localMaterials == [material])
    let stored = try await AgentChatStorage(root: root.appendingPathComponent(controller.triptychID.uuidString)).load()
    #expect(stored.first { $0.id == owner }?.messages.first?.localMaterials == [material])
    for origin in [AgentChatLocalMaterial.CaptureOrigin.clipboard, .drop] {
      let count = controller.selected?.messages.count
      await controller.addTransferredMaterials([.image(bytes)], origin: origin, to: owner)
      let captured = try #require(controller.selected?.localMaterials.first)
      #expect(captured.source == .imageCapture(origin) && captured.fingerprint == DocumentFingerprint(data: bytes))
      #expect(controller.selected?.messages.count == count && controller.selected?.pendingMessageID == nil)
      controller.editDraft("Discuss the captured figure.")
      controller.send()
      try await wait { !controller.isBusy && controller.selected?.pendingMessageID == nil }
      let capturedTurn = try JSONDecoder().decode(MCPJSONValue.self, from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json")))
      let expectedOrigin = origin == .clipboard ? "explicitly pasted clipboard image" : "explicitly dropped image"
      #expect(capturedTurn.objectValue?["input"]?.arrayValue?.first?.objectValue?["text"]?.stringValue?.contains(expectedOrigin) == true)
      #expect(controller.selected?.messages.last(where: { $0.role == .user })?.localMaterials == [captured])
      let saved = try await AgentChatStorage(root: root.appendingPathComponent(controller.triptychID.uuidString)).load()
      #expect(saved.first { $0.id == owner }?.messages.last(where: { $0.role == .user })?.localMaterials == [captured])
    }
    let text = root.appendingPathComponent("source.txt")
    try Data("Exact source".utf8).write(to: text)
    await controller.addLocalFiles([text], to: owner)
    let staged = try #require(controller.selected?.localMaterials.first)
    let copy = try await controller.previewLocalMaterial(staged)
    try FileManager.default.removeItem(at: copy)
    controller.editDraft("Keep this question.")
    let count = controller.selected?.messages.count
    controller.send()
    try await wait { !controller.isBusy }
    #expect(controller.materialErrors[owner] != nil && controller.selected?.draft == "Keep this question.")
    #expect(controller.selected?.pendingMessageID == nil && controller.selected?.messages.count == count)
    await controller.addLocalFiles([text], to: owner, replacing: staged.id)
    #expect(controller.selected?.localMaterials.count == 1 && controller.selected?.localMaterials.first?.id != staged.id)
    let replacement = try #require(controller.selected?.localMaterials.first)
    controller.removeLocalMaterial(replacement.id, from: owner)
    #expect(controller.selected?.localMaterials.isEmpty == true)
    #expect(try Data(contentsOf: file) == bytes && controller.selected?.messages.first?.localMaterials == [material])
    await controller.disconnect()
  }
}
