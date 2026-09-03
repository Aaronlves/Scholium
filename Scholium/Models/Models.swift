import ScholiumContracts
import Foundation

struct MarkdownReviewSelection: Equatable, Sendable {
  let startLine: Int
  let endLine: Int
  let excerpt: String
  let utf16LowerBound: Int?
  let utf16UpperBound: Int?
  let contextBefore: String
  let contextAfter: String

  init(
    startLine: Int,
    endLine: Int,
    excerpt: String,
    utf16LowerBound: Int? = nil,
    utf16UpperBound: Int? = nil,
    contextBefore: String = "",
    contextAfter: String = ""
  ) {
    self.startLine = startLine
    self.endLine = endLine
    self.excerpt = excerpt
    self.utf16LowerBound = utf16LowerBound
    self.utf16UpperBound = utf16UpperBound
    self.contextBefore = contextBefore
    self.contextAfter = contextAfter
  }

  var exactUTF16Range: Range<Int>? {
    guard let utf16LowerBound, let utf16UpperBound,
          utf16UpperBound > utf16LowerBound else { return nil }
    return utf16LowerBound..<utf16UpperBound
  }

}

// MARK: - Workflow Profile

/// A note's semantic role is derived from the registered vault.
enum NoteProfile: String, Codable, Hashable {
  case paperAnalysis
  case topicKnowledge
  case draftProject
  case generic

  static func infer(vaultRole: VaultRole) -> Self {
    let resolved = WorkflowProfileResolver.resolve(vaultRole: vaultRole)
    switch resolved {
    case .analysis: return .paperAnalysis
    case .topicMarkdown: return .topicKnowledge
    case .draftProject: return .draftProject
    case .genericMarkdown: return .generic
    }
  }

  var displayName: String {
    switch self {
    case .paperAnalysis: ScholiumL10n.dynamicString("Analysis")
    case .topicKnowledge: ScholiumL10n.dynamicString("Topic")
    case .draftProject: ScholiumL10n.dynamicString("Work")
    case .generic: "Markdown"
    }
  }
}

// MARK: - Window Document Location

/// One window-visible document location backed by the shared immutable
/// Application snapshot for its exact Triptych vault.
enum WindowDocumentLocation: Identifiable, Hashable, Sendable {
  enum ID: Hashable, Sendable {
    case workspace(VaultQualifiedNoteID)
  }

  case workspace(WorkspaceNoteSnapshot)

  var id: ID {
    switch self {
    case .workspace(let snapshot): .workspace(snapshot.id)
    }
  }

  var workspaceSnapshot: WorkspaceNoteSnapshot? {
    guard case .workspace(let snapshot) = self else { return nil }
    return snapshot
  }

  var document: NoteDocument {
    switch self {
    case .workspace(let snapshot): snapshot.document
    }
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.workspace(let lhs), .workspace(let rhs)):
      lhs == rhs
    }
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(document.fingerprint)
    switch self {
    case .workspace(let snapshot): hasher.combine(snapshot)
    }
  }
}

extension WindowDocumentLocation {
  /// Synthetic workspace-backed Note used only by SwiftUI previews and the
  /// component catalog. Production construction continues to consume an
  /// Application-owned `WorkspaceNoteSnapshot`.
  static func syntheticPreview(
    relativePath: String,
    rawContent: String,
    vaultRole: VaultRole = .other,
    managedMetadata: [String: YAMLValue] = [:]
  ) -> Self {
    let noteID = UUID()
    let document = NoteDocument(
      relativePath: relativePath,
      rawContent: rawContent
    )
    return .workspace(WorkspaceNoteSnapshot(
      id: VaultQualifiedNoteID(
        vaultID: UUID(),
        relativePath: relativePath
      ),
      vaultRole: vaultRole,
      stableIdentity: .resolved(noteID),
      document: document,
      fileMetadata: WorkspaceFileMetadata(
        byteCount: document.sourceBytes.count,
        creationDate: nil,
        modificationDate: nil
      ),
      graphCounts: WorkspaceGraphCounts(
        incoming: 0,
        outgoing: 0,
        broken: 0,
        ambiguous: 0
      ),
      metadata: managedMetadata.isEmpty ? nil : NoteMetadataSnapshot(
        record: NoteMetadataRecord(noteID: noteID, fields: managedMetadata),
        revision: DocumentFingerprint(content: "preview-metadata")
      )
    ))
  }
}

extension WindowDocumentLocation {
  var vaultID: UUID {
    switch self {
    case .workspace(let snapshot): snapshot.id.vaultID
    }
  }
  var relativePath: String { document.relativePath }
  var fileName: String { (relativePath as NSString).lastPathComponent }
  var displayName: String {
    if let cached = workspaceSnapshot?.cachedTitleProjection {
      return cached.title
    }
    return ResearchNoteTitleResolver.resolve(document: document)
  }
  var vaultRole: VaultRole { workspaceSnapshot?.vaultRole ?? .other }
  var profile: NoteProfile {
    NoteProfile.infer(vaultRole: vaultRole)
  }
  /// Malformed frontmatter remains readable as exact source. Structured
  /// properties use only Core's parsed projection and never reconstruct bytes.
  var frontmatter: [String: YAMLValue] { document.parsedFrontmatter }
  var body: String {
    document.validationWarnings.isEmpty ? document.body : document.rawContent
  }
  var rawContent: String { document.rawContent }

  var title: String? { displayName }
  var aliases: [String] {
    managedMetadataFields["aliases"]?.canonicalStringList ?? []
  }
  var tags: [String] { frontmatter["keywords"]?.canonicalStringList ?? [] }
  var authors: [String] {
    managedMetadataFields["authors"]
      .flatMap { PropertyContractCatalog.creatorNames(from: $0) }?
      .map(\.displayName) ?? []
  }
  /// Exact lookup for the two authored YAML keys Scholium recognizes. Unknown
  /// YAML remains Source-only even when a caller supplies its exact spelling.
  func authoredYAMLValue(named key: String) -> YAMLValue? {
    guard PropertyContractCatalog.contract(for: key, profile: schemaProfile) != nil else {
      return nil
    }
    return frontmatter[key]
  }

  var managedMetadataFields: [String: YAMLValue] {
    workspaceSnapshot?.metadata?.record.fields ?? [:]
  }

  func managedMetadataValue(named key: String) -> YAMLValue? {
    managedMetadataFields[key]
  }

  func authoredTopLevelScalarToken(named key: String) -> String? {
    guard PropertyContractCatalog.contract(for: key, profile: schemaProfile) != nil else {
      return nil
    }
    guard let frontmatter = document.rawFrontmatter else { return nil }
    return try? FrontmatterPatchPlanner.authoredScalarToken(
      frontmatter: frontmatter,
      key: key,
      newline: document.newlineStyle.sequence
    )
  }

  var fileModifiedAt: Date {
    workspaceSnapshot?.fileMetadata.modificationDate ?? .distantPast
  }

  var schemaProfile: SchemaProfileID {
    workspaceSnapshot?.schemaProfile
      ?? WorkflowProfileResolver.resolve(vaultRole: vaultRole)
  }

  func semanticProperty(
    at keyPath: String,
    catalog: NoteMetadataCatalog
  ) -> YAMLValue? {
    let parts = keyPath.split(separator: ".", maxSplits: 1).map(String.init)
    guard let rootKey = parts.first else { return nil }
    let root: YAMLValue?
    if PropertyContractCatalog.contract(for: rootKey, profile: schemaProfile) != nil {
      root = frontmatter[rootKey]
    } else if catalog.contract(for: rootKey, profile: schemaProfile) != nil {
      root = managedMetadataFields[rootKey]
    } else {
      return nil
    }
    guard let root else { return nil }
    guard parts.count == 2 else { return root }
    guard case .object(let values) = root else { return nil }
    return values[parts[1]]
  }

  func filterableProperties(
    catalog: NoteMetadataCatalog
  ) -> [String: [String]] {
    var result: [String: [String]] = [:]
    for contract in PropertyContractCatalog.contracts(for: schemaProfile) {
      guard let value = frontmatter[contract.canonicalKey] else { continue }
      result[contract.canonicalKey] = value.appFilterValues
    }
    for contract in catalog.contracts(for: schemaProfile) {
      let key = contract.canonicalKey
      guard let value = managedMetadataFields[key] else { continue }
      if contract.valueKind == .creatorList,
         let creators = PropertyContractCatalog.creatorNames(from: value) {
        result[key] = creators.map(\.displayName)
      } else {
        result[key] = value.appFilterValues
      }
    }
    return result
  }
}

extension YAMLValue {
  var appArrayValue: [String] {
    switch self {
    case .array(let values):
      values.map(\.displayScalar)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    case .string(let value):
      value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [value]
    default:
      scalarString.map { [$0] } ?? []
    }
  }

  var appIntValue: Int? {
    switch self {
    case .integer(let value): value
    case .double(let value) where value.rounded() == value: Int(value)
    case .string(let value): Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    default: nil
    }
  }

  var appDateValue: Date? {
    guard let value = scalarString else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
    return formatter.date(from: value)
  }

  var appFilterValues: [String] {
    switch self {
    case .string(let value): [value]
    case .integer(let value): [String(value)]
    case .double(let value): [String(value)]
    case .boolean(let value): [value ? "true" : "false"]
    case .null: []
    case .array(let values): values.map(\.displayScalar)
    case .object: []
    }
  }
}
extension Array where Element == WindowDocumentLocation {
  /// Stable tag projection derived from the exact Core document.
  var orderedTags: [String] {
    var counts: [String: Int] = [:]
    for note in self {
      for tag in note.tags {
        let normalized = tag.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { continue }
        counts[normalized, default: 0] += 1
      }
    }
    return counts.keys.sorted { left, right in
      let leftCount = counts[left, default: 0]
      let rightCount = counts[right, default: 0]
      return leftCount == rightCount ? left < right : leftCount > rightCount
    }
  }
}

// MARK: - Vault Configuration

struct VaultConfig: Codable {
  let path: URL
  let name: String
  let obsidianConfig: ObsidianConfig?

  struct ObsidianConfig: Codable {
    var vaultName: String?
    var theme: String?         // "obsidian" or custom theme name
    var showLineNumbers: Bool?
    var defaultViewMode: String?  // "source" or "preview"
    var attachmentFolderPath: String?
    var newLinkFormat: String?    // "shortest" or "relative" or "absolute"
  }
}
