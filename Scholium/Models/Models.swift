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

  var lineDescription: String {
    startLine == endLine ? "Line \(startLine)" : "Lines \(startLine)–\(endLine)"
  }
}

// MARK: - Knowledge Base Type

enum KnowledgeBase: String, Codable, CaseIterable, Hashable {
  case papers
  case topics
  case output

  var displayName: String {
    switch self {
    case .papers: return ScholiumL10n.dynamicString("Analyses")
    case .topics: return ScholiumL10n.dynamicString("Topics")
    case .output: return ScholiumL10n.dynamicString("Works")
    }
  }

  var icon: String {
    switch self {
    case .papers: return "doc.text"
    case .topics: return "lightbulb"
    case .output: return "pencil.and.outline"
    }
  }

  static func infer(from path: String) -> KnowledgeBase? {
    if path.hasPrefix("papers/") || path.contains("/papers/") { return .papers }
    if path.hasPrefix("topics/") || path.contains("/topics/") { return .topics }
    if path.hasPrefix("output/") || path.contains("/output/") { return .output }
    return nil
  }
}

// MARK: - Workflow Profile

/// A note's semantic role is derived from the registered vault.
enum NoteProfile: String, Codable, Hashable {
  case paperAnalysis
  case topicKnowledge
  case draftProject
  case generic

  static func infer(
    vaultRole: VaultRole,
    frontmatter: [String: YAMLValue],
    relativePath: String
  ) -> Self {
    let resolved = WorkflowProfileResolver.resolve(
      vaultRole: vaultRole,
      frontmatter: frontmatter,
      relativePath: relativePath
    )
    switch resolved {
    case .analysis: return .paperAnalysis
    case .topicMarkdown: return .topicKnowledge
    case .draftProject: return .draftProject
    case .genericMarkdown: return .generic
    }
  }

  var knowledgeBase: KnowledgeBase {
    switch self {
    case .paperAnalysis: .papers
    case .topicKnowledge: .topics
    case .draftProject, .generic: .output
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

/// Researcher-facing property policy. Keys hidden here remain present in the
/// exact Markdown source and in the agent-facing semantic projection.
enum ResearcherPropertyPolicy {
  static let explicitlyHiddenKeys: Set<String> = [
    "id", "record_type", "schema_version", "paper_id", "note_id",
    "status", "deadline",
    "zotero_item_key", "zotero_attachment_key", "zotero_citation_key",
    "zoterokey", "citation_key", "citationkey", "citekey",
    "main_topic", "related_topics", "follow_up",
    "primary_cluster", "secondary_clusters", "follow_up_leads",
  ]

  /// These values remain useful to display, but structured editing must not
  /// make machine history or provenance look like researcher-authored YAML.
  /// Exact Source mode remains available when the researcher intentionally
  /// needs to assume responsibility for such a change.
  static let structuredEditingProtectedKeys: Set<String> = [
    "created", "updated", "modified", "analysis_created_at", "analysis_updated_at",
    "created_at", "updated_at", "last_modified_by", "last_modified_at",
    "origin", "provenance", "last_reviewed",
  ]

  static func isHidden(_ key: String) -> Bool {
    let normalized = key.lowercased()
    if explicitlyHiddenKeys.contains(normalized) { return true }
    return normalized.hasSuffix("_id") || normalized.hasSuffix("_key")
  }

  static func isHumanEditable(_ key: String) -> Bool {
    let normalized = key.lowercased()
    return !isHidden(normalized)
      && !structuredEditingProtectedKeys.contains(normalized)
      && !normalized.contains(".")
  }
}

// MARK: - Window Document Location

/// A validated structured edit for the optional role-aware Research Unit.
/// Removing the mapping is explicit; an empty or malformed mapping is never
/// emitted by the Properties editor.
enum ResearchUnitEdit: Hashable, Sendable {
  case set(completion: AnalysisCompletion?, scope: String?, limitations: [String])
  case remove

  var coreValue: FrontmatterEditValue {
    switch self {
    case .set(let completion, let scope, let limitations):
      var values: [String: FrontmatterEditValue] = [:]
      if let completion {
        values["completion"] = .string(completion.yamlScalar)
      }
      if let scope {
        values["scope"] = .string(scope)
      }
      if !limitations.isEmpty {
        values["limitations"] = .array(limitations)
      }
      return .mapping(values)
    case .remove:
      return .remove
    }
  }
}

/// One window-visible document location. Workspace documents retain the shared
/// immutable Application snapshot; Unclassified documents retain the exact Core
/// document without inventing a vault or portable identity.
enum WindowDocumentLocation: Identifiable, Hashable, Sendable {
  enum ID: Hashable, Sendable {
    case workspace(VaultQualifiedNoteID)
    case unclassified(String)
  }

  case workspace(WorkspaceNoteSnapshot)
  case unclassified(NoteDocument)

  var id: ID {
    switch self {
    case .workspace(let snapshot): .workspace(snapshot.id)
    case .unclassified(let document): .unclassified(document.relativePath)
    }
  }

  var workspaceSnapshot: WorkspaceNoteSnapshot? {
    guard case .workspace(let snapshot) = self else { return nil }
    return snapshot
  }

  var document: NoteDocument {
    switch self {
    case .workspace(let snapshot): snapshot.document
    case .unclassified(let document): document
    }
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.workspace(let lhs), .workspace(let rhs)):
      lhs == rhs
    case (.unclassified(let lhs), .unclassified(let rhs)):
      lhs.relativePath == rhs.relativePath && lhs.fingerprint == rhs.fingerprint
    default:
      false
    }
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(document.fingerprint)
    if case .workspace(let snapshot) = self {
      hasher.combine(snapshot)
    }
  }
}

extension WindowDocumentLocation {
  var relativePath: String { document.relativePath }
  var fileName: String { (relativePath as NSString).lastPathComponent }
  var displayName: String {
    if let cached = workspaceSnapshot?.cachedTitleProjection {
      return cached.resolution.title
    }
    return ResearchNoteTitleResolver.resolve(
      document: document,
      profile: schemaProfile
    ).title
  }
  var vaultRole: VaultRole { workspaceSnapshot?.vaultRole ?? .other }
  var profile: NoteProfile {
    NoteProfile.infer(
      vaultRole: vaultRole,
      frontmatter: frontmatter,
      relativePath: relativePath
    )
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
    (frontmatter["aliases"] ?? frontmatter["alias"])?.appArrayValue ?? []
  }
  var tags: [String] { frontmatter["tags"]?.appArrayValue ?? [] }
  var year: Int? { frontmatter["year"]?.appIntValue }
  var authors: [String] { frontmatter["authors"]?.appArrayValue ?? [] }
  var debateImportance: Int? {
    guard case .integer(let rating)? = property(at: "debate_importance"),
          let contract = propertyContract(for: "debate_importance"),
          contract.containsInteger(rating) else { return nil }
    return rating
  }
  var researchUnit: ResearchUnitDeclaration {
    ResearchUnitDeclaration(
      frontmatter: document.parsedFrontmatter,
      profile: schemaProfile
    )
  }
  var created: Date? { property(at: "created")?.appDateValue }
  var modified: Date? { property(at: "updated")?.appDateValue }

  var fileModifiedAt: Date {
    workspaceSnapshot?.fileMetadata.modificationDate ?? .distantPast
  }

  var schemaProfile: SchemaProfileID {
    workspaceSnapshot?.schemaProfile
      ?? WorkflowProfileResolver.resolve(
        vaultRole: vaultRole,
        frontmatter: frontmatter,
        relativePath: relativePath
      )
  }

  func property(at keyPath: String) -> YAMLValue? {
    let parts = keyPath.split(separator: ".", maxSplits: 1).map(String.init)
    guard let rootKey = parts.first else { return nil }
    let contract = propertyContract(for: rootKey)
    let canonicalKey = contract?.canonicalKey ?? rootKey
    let root = frontmatter[canonicalKey]
    guard let root else { return nil }
    guard parts.count == 2 else { return root }
    guard case .object(let values) = root else { return nil }
    return values[parts[1]]
  }

  /// Prefer the note's resolved profile, then consult the complete Core
  /// catalog for recognized canonical properties whose semantic home is
  /// another current profile.
  private func propertyContract(for key: String) -> PropertyContract? {
    if let contract = PropertyContractCatalog.contract(for: key, profile: schemaProfile) {
      return contract
    }
    for profile in SchemaProfileID.allCases {
      if let contract = PropertyContractCatalog.contract(for: key, profile: profile) {
        return contract
      }
    }
    return nil
  }

  var filterableProperties: [String: [String]] {
    var result: [String: [String]] = [:]
    let inactiveAnalysisKeys: Set<String>
    switch schemaProfile {
    case .analysis:
      inactiveAnalysisKeys = ["relevance"]
    default:
      inactiveAnalysisKeys = []
    }
    for (key, value) in frontmatter
      where !inactiveAnalysisKeys.contains(key)
        && !ResearcherPropertyPolicy.isHidden(key) {
      if case .object(let nested) = value {
        for (path, nestedValue) in YAMLValue.object(nested).flattenedScalarValues {
          result["\(key).\(path)"] = [nestedValue]
        }
      } else {
        result[key] = value.appFilterValues
      }
    }
    let canonicalKeys = Set(SchemaProfileID.allCases.flatMap { profile in
      PropertyContractCatalog.contracts(for: profile).map(\.canonicalKey)
    })
    for canonicalKey in canonicalKeys where result[canonicalKey] == nil {
      if let value = property(at: canonicalKey) {
        result[canonicalKey] = value.appFilterValues
      }
    }
    return result
  }
}

private extension PropertyContract {
  func containsInteger(_ value: Int) -> Bool {
    for constraint in constraints {
      if case .integerRange(let minimum, let maximum) = constraint {
        return (minimum...maximum).contains(value)
      }
    }
    return false
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
