import Foundation
import ScholiumCore

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
    case .papers: return "Analyses"
    case .topics: return "Topics"
    case .output: return "Works"
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

/// A note's semantic role is derived from the registered vault first, then
/// from explicit schema metadata, and only then from legacy folder names.
enum NoteProfile: String, Codable, Hashable {
  case paperAnalysis
  case topicKnowledge
  case dissertationControl
  case draftProject
  case generic

  static func infer(
    vaultRole: VaultRole,
    frontmatter: [String: FrontmatterValue],
    relativePath: String
  ) -> Self {
    let resolved = WorkflowProfileResolver.resolve(
      vaultRole: vaultRole,
      frontmatter: frontmatter.mapValues(\.workflowYAMLValue),
      relativePath: relativePath
    )
    switch resolved {
    case .paperAnalysisV1: return .paperAnalysis
    case .topicMarkdown: return .topicKnowledge
    case .dissertationControlV3, .dissertationControlV4: return .dissertationControl
    case .draftProject: return .draftProject
    case .genericMarkdown: return .generic
    }
  }

  var knowledgeBase: KnowledgeBase {
    switch self {
    case .paperAnalysis: .papers
    case .topicKnowledge: .topics
    case .dissertationControl, .draftProject, .generic: .output
    }
  }

  var displayName: String {
    switch self {
    case .paperAnalysis: "Analysis"
    case .topicKnowledge: "Topic"
    case .dissertationControl: "Dissertation Control"
    case .draftProject: "Work"
    case .generic: "Markdown"
    }
  }
}

/// Researcher-facing property policy. Keys hidden here remain present in the
/// exact Markdown source and in the agent-facing semantic projection.
enum ResearcherPropertyPolicy {
  static let explicitlyHiddenKeys: Set<String> = [
    "id", "record_type", "schema_version", "paper_id", "note_id",
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

// MARK: - Note Model

struct Note: Codable, Identifiable, Hashable {
  var id: String { relativePath }

  let relativePath: String     // e.g. "papers/smith2023-attention.md"
  let fileName: String         // e.g. "smith2023-attention.md"
  let displayName: String      // e.g. "smith2023-attention"
  let kb: KnowledgeBase
  let profile: NoteProfile

  // Content
  var frontmatter: [String: FrontmatterValue]
  var body: String
  var rawContent: String       // original file content (for diff)

  // Frontmatter convenience accessors
  var title: String? { frontmatter["title"]?.stringValue }
  var aliases: [String] {
    let values = frontmatter["aliases"]?.arrayValue
      ?? frontmatter["alias"]?.arrayValue
      ?? []
    return values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
  var tags: [String] { frontmatter["tags"]?.arrayValue ?? [] }
  var status: String? {
    frontmatter["status"]?.stringValue
      ?? frontmatter["analysis_status"]?.stringValue
      ?? frontmatter["lifecycle_status"]?.stringValue
  }
  var governanceReviewStatus: String? { frontmatter["review_status"]?.stringValue }
  var prosePermission: String? { frontmatter["prose_permission"]?.stringValue }
  var year: Int? {
    frontmatter["year"]?.intValue
      ?? frontmatter["year"]?.stringValue.flatMap {
        Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
      }
  }
  var authors: [String] { frontmatter["authors"]?.arrayValue ?? [] }
  var doi: String? {
    frontmatter["doi"]?.stringValue ?? frontmatter["DOI"]?.stringValue
  }
  var isbn: String? {
    frontmatter["isbn"]?.stringValue ?? frontmatter["ISBN"]?.stringValue
  }
  var zoteroCitationKey: String? {
    frontmatter["zotero_citation_key"]?.stringValue
      ?? frontmatter["citation_key"]?.stringValue
      ?? frontmatter["citationKey"]?.stringValue
      ?? frontmatter["citationkey"]?.stringValue
      ?? frontmatter["citekey"]?.stringValue
  }
  var zoteroKey: String? {
    frontmatter["zotero_item_key"]?.stringValue
      ?? frontmatter["zoteroKey"]?.stringValue
      ?? frontmatter["zotero-key"]?.stringValue
  }
  var zoteroSourceIdentity: ZoteroSourceIdentity {
    ZoteroSourceIdentity(
      itemKey: zoteroKey,
      doi: doi,
      isbn: isbn,
      citationKey: zoteroCitationKey,
      title: title,
      authors: authors,
      year: year
    )
  }
  var created: Date? { property(at: "created")?.dateValue }
  var modified: Date? { property(at: "updated")?.dateValue }

  // App-managed fields (not in file frontmatter, stored in app index)
  var isReviewed: Bool
  var reviewedAt: Date?
  var wordCount: Int
  var linkCount: Int
  var backlinkCount: Int
  var fileModifiedAt: Date     // filesystem mtime

  init(
    relativePath: String,
    frontmatter: [String: FrontmatterValue],
    body: String,
    rawContent: String,
    vaultRole: VaultRole = .other,
    isReviewed: Bool = false,
    reviewedAt: Date? = nil,
    fileModifiedAt: Date = Date()
  ) {
    self.relativePath = relativePath
    self.fileName = (relativePath as NSString).lastPathComponent
    self.displayName = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
    self.profile = NoteProfile.infer(
      vaultRole: vaultRole,
      frontmatter: frontmatter,
      relativePath: relativePath
    )
    self.kb = profile.knowledgeBase
    self.frontmatter = frontmatter
    self.body = body
    self.rawContent = rawContent
    self.isReviewed = isReviewed
    self.reviewedAt = reviewedAt
    self.wordCount = body.split(separator: " ").count
    self.linkCount = 0
    self.backlinkCount = 0
    self.fileModifiedAt = fileModifiedAt
  }

  func property(at keyPath: String) -> FrontmatterValue? {
    let parts = keyPath.split(separator: ".", maxSplits: 1).map(String.init)
    let root = frontmatter[parts[0]] ?? (TriptychProperty.legacyAliases[parts[0]] ?? [])
      .compactMap { frontmatter[$0] }
      .first
    guard let root else { return nil }
    guard parts.count == 2 else { return root }
    guard case .dictionary(let values) = root, let value = values[parts[1]] else { return nil }
    return .string(value)
  }

  var filterableProperties: [String: [String]] {
    var result: [String: [String]] = [:]
    for (key, value) in frontmatter {
      if case .dictionary(let nested) = value {
        for (nestedKey, nestedValue) in nested {
          result["\(key).\(nestedKey)"] = [nestedValue]
        }
      } else {
        result[key] = value.filterValues
      }
    }
    for canonicalKey in TriptychProperty.legacyAliases.keys where result[canonicalKey] == nil {
      if let value = property(at: canonicalKey) {
        result[canonicalKey] = value.filterValues
      }
    }
    return result
  }
}

// MARK: - Frontmatter Value

enum FrontmatterValue: Codable, Hashable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
  case date(Date)
  case array([String])
  case dictionary([String: String])

  var stringValue: String? {
    if case .string(let v) = self { return v }; return nil
  }
  var intValue: Int? {
    if case .int(let v) = self { return v }; return nil
  }
  var boolValue: Bool? {
    if case .bool(let v) = self { return v }; return nil
  }
  var dateValue: Date? {
    if case .date(let v) = self { return v }
    if case .string(let v) = self {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
      return formatter.date(from: v)
    }
    return nil
  }
  var arrayValue: [String] {
    if case .array(let v) = self { return v }
    if case .string(let v) = self { return [v] }
    return []
  }
  var dictValue: [String: String]? {
    if case .dictionary(let v) = self { return v }; return nil
  }

  var workflowYAMLValue: YAMLValue {
    switch self {
    case .string(let value): .string(value)
    case .int(let value): .integer(value)
    case .double(let value): .double(value)
    case .bool(let value): .boolean(value)
    case .date(let value): .string(value.formatted(.iso8601))
    case .array(let values): .array(values.map(YAMLValue.string))
    case .dictionary(let values): .object(values.mapValues(YAMLValue.string))
    }
  }

  /// Stable, human-readable values suitable for equality filters. Nested
  /// dictionaries are intentionally excluded because flattening them would
  /// erase provenance and structure.
  var filterValues: [String] {
    switch self {
    case .string(let value): [value]
    case .int(let value): [String(value)]
    case .double(let value): [String(value)]
    case .bool(let value): [value ? "true" : "false"]
    case .date(let value): [value.formatted(.iso8601.year().month().day())]
    case .array(let values): values
    case .dictionary: []
    }
  }
}

// MARK: - Frontmatter Schema (Per-KB Field Definitions)

struct FrontmatterSchema: Codable, Hashable {
  let kb: KnowledgeBase
  let fields: [FieldDefinition]

  struct FieldDefinition: Codable, Hashable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let type: FieldType
    let required: Bool
    let autoFilled: Bool
    let description: String?
    let allowedValues: [String]?  // for enum/status fields

    enum FieldType: String, Codable, Hashable {
      case string
      case text          // multiline string
      case number
      case date
      case boolean
      case tags          // array of strings, tag-style UI
      case array         // array of strings
      case `enum`        // pick from allowedValues
      case zoteroKey     // special: Zotero item key
      case doi           // special: DOI with link
    }
  }

  static let papers = FrontmatterSchema(kb: .papers, fields: [
    FieldDefinition(key: "title", label: "Title", type: .string, required: true, autoFilled: false, description: "Title of the analyzed source.", allowedValues: nil),
    FieldDefinition(key: "authors", label: "Authors", type: .array, required: true, autoFilled: false, description: nil, allowedValues: nil),
    FieldDefinition(key: "year", label: "Year", type: .number, required: true, autoFilled: false, description: nil, allowedValues: nil),
    FieldDefinition(key: "type", label: "Type", type: .enum, required: false, autoFilled: false, description: "Publication form, not philosophical role.", allowedValues: ["journal_article", "book", "book_chapter", "handbook_chapter", "encyclopedia_entry", "thesis", "manuscript", "other"]),
    FieldDefinition(key: "tags", label: "Tags", type: .tags, required: false, autoFilled: false, description: nil, allowedValues: nil),
    FieldDefinition(key: "access", label: "Access", type: .enum, required: false, autoFilled: false, description: "Extent of source material available for the analysis.", allowedValues: ["full_text", "partial_text", "metadata_only", "unavailable"]),
    FieldDefinition(key: "text_reliability", label: "Text Reliability", type: .enum, required: false, autoFilled: false, description: "Reliability of the text actually consulted.", allowedValues: ["verified", "usable_with_caution", "unreliable"]),
    FieldDefinition(key: "locators", label: "Locators", type: .enum, required: false, autoFilled: false, description: "Whether citations can be checked at stable locations.", allowedValues: ["reliable", "partial", "unverified", "unavailable"]),
    FieldDefinition(key: "status", label: "Status", type: .enum, required: false, autoFilled: false, description: "State of the analysis, not a judgment about the source.", allowedValues: ["draft", "complete", "reviewed"]),
    FieldDefinition(key: "relevance", label: "Relevance", type: .number, required: false, autoFilled: false, description: "Integer from 1 to 10 for local research relevance; not source quality.", allowedValues: nil),
    FieldDefinition(key: "created", label: "Created", type: .date, required: false, autoFilled: true, description: "Analysis creation date when the vault records it.", allowedValues: nil),
    FieldDefinition(key: "updated", label: "Updated", type: .date, required: false, autoFilled: true, description: "Updated on a successful save.", allowedValues: nil),
  ])

  static let topics = FrontmatterSchema(kb: .topics, fields: [
    FieldDefinition(key: "title", label: "Title", type: .string, required: false, autoFilled: false, description: "Optional Obsidian property; filename and headings remain valid structure.", allowedValues: nil),
    FieldDefinition(key: "aliases", label: "Aliases", type: .array, required: false, autoFilled: false, description: "Alternative names used for finding and linking the topic.", allowedValues: nil),
    FieldDefinition(key: "tags", label: "Tags", type: .tags, required: false, autoFilled: false, description: nil, allowedValues: nil),
    FieldDefinition(key: "status", label: "Status", type: .enum, required: false, autoFilled: false, description: "Development of the note, not settlement of the topic.", allowedValues: ["seed", "developing", "maintained"]),
    FieldDefinition(key: "created", label: "Created", type: .date, required: false, autoFilled: false, description: "Preserved only when the note already uses it.", allowedValues: nil),
    FieldDefinition(key: "updated", label: "Updated", type: .date, required: false, autoFilled: false, description: "Preserved only when the note already uses it; topic saves do not inject YAML.", allowedValues: nil),
  ])

  static let output = FrontmatterSchema(kb: .output, fields: [
    FieldDefinition(key: "title", label: "Title", type: .string, required: true, autoFilled: false, description: "Title of the work.", allowedValues: nil),
    FieldDefinition(key: "authors", label: "Authors", type: .array, required: false, autoFilled: false, description: "Use for co-authored work; omit for an ordinary single-author vault.", allowedValues: nil),
    FieldDefinition(key: "kind", label: "Kind", type: .enum, required: false, autoFilled: false, description: "Optional form of the authored work.", allowedValues: ["paper", "chapter", "book", "talk", "review", "teaching", "other"]),
    FieldDefinition(key: "tags", label: "Tags", type: .tags, required: false, autoFilled: false, description: nil, allowedValues: nil),
    FieldDefinition(key: "status", label: "Status", type: .enum, required: false, autoFilled: false, description: "Production state, not philosophical quality or acceptance probability.", allowedValues: ["planning", "drafting", "revising", "review", "ready", "submitted", "published", "archived"]),
    FieldDefinition(key: "venue", label: "Venue", type: .string, required: false, autoFilled: false, description: "Journal, publisher, course, event, or other destination.", allowedValues: nil),
    FieldDefinition(key: "deadline", label: "Deadline", type: .date, required: false, autoFilled: false, description: nil, allowedValues: nil),
    FieldDefinition(key: "created", label: "Created", type: .date, required: false, autoFilled: true, description: "Creation date when the vault records it.", allowedValues: nil),
    FieldDefinition(key: "updated", label: "Updated", type: .date, required: false, autoFilled: true, description: "Updated on a successful save when already used by the note.", allowedValues: nil),
  ])

  static let dissertationControl = FrontmatterSchema(kb: .output, fields: [
    FieldDefinition(key: "note_type", label: "Note Type", type: .string, required: true, autoFilled: false, description: "Dossier, registry, spine, import packet, control note, or other governance class.", allowedValues: nil),
    FieldDefinition(key: "project_role", label: "Project Role", type: .string, required: true, autoFilled: false, description: nil, allowedValues: nil),
    FieldDefinition(key: "claim_type", label: "Claim Type", type: .string, required: true, autoFilled: false, description: nil, allowedValues: nil),
    FieldDefinition(key: "status", label: "Working Status", type: .string, required: true, autoFilled: false, description: "Workflow state, not publication status.", allowedValues: nil),
    FieldDefinition(key: "settlement_dimensions", label: "Settlement Dimensions", type: .array, required: true, autoFilled: false, description: nil, allowedValues: nil),
    FieldDefinition(key: "settlement_degree", label: "Settlement Degree", type: .string, required: true, autoFilled: false, description: nil, allowedValues: nil),
    FieldDefinition(key: "review_status", label: "Governance Review", type: .string, required: true, autoFilled: false, description: "Philosophical/research approval state; separate from Scholium's exact-bytes review.", allowedValues: nil),
    FieldDefinition(key: "confidence", label: "Working Confidence", type: .enum, required: true, autoFilled: false, description: nil, allowedValues: ["low", "medium", "high"]),
    FieldDefinition(key: "prose_permission", label: "Prose Permission", type: .string, required: true, autoFilled: false, description: "Whether and how chapter prose may use this record.", allowedValues: nil),
    FieldDefinition(key: "last_reviewed", label: "Last Substantive Review", type: .date, required: true, autoFilled: false, description: "Changed only by an explicit substantive-review action.", allowedValues: nil),
    FieldDefinition(key: "reopen_condition", label: "Reopen Condition", type: .text, required: true, autoFilled: false, description: nil, allowedValues: nil),
    FieldDefinition(key: "privacy", label: "Privacy", type: .string, required: true, autoFilled: false, description: nil, allowedValues: nil),
    FieldDefinition(key: "version", label: "Specification Version", type: .string, required: false, autoFilled: true, description: "Control-note-only field; displayed without normalization.", allowedValues: nil),
    FieldDefinition(key: "design_decisions", label: "Design Decisions", type: .array, required: false, autoFilled: true, description: "Control-note-only field; displayed read-only.", allowedValues: nil),
  ])

  static let dissertationControlV4 = FrontmatterSchema(kb: .output, fields: [
    FieldDefinition(key: "title", label: "Title", type: .string, required: true, autoFilled: false, description: "Should match the first H1.", allowedValues: nil),
    FieldDefinition(key: "note_type", label: "Note Type", type: .enum, required: true, autoFilled: false, description: "Atomic or control-record identity; temporary argument roles belong in relations.", allowedValues: DissertationControlV4.noteTypes.sorted()),
    FieldDefinition(key: "project_role", label: "Project Role", type: .enum, required: true, autoFilled: false, description: "Structural role, not premise, conclusion, target, objection, or reply.", allowedValues: DissertationControlV4.projectRoles.sorted()),
    FieldDefinition(key: "origin", label: "Origin", type: .enum, required: true, autoFilled: false, description: "Whose content or reconstruction the record represents.", allowedValues: DissertationControlV4.origins.sorted()),
    FieldDefinition(key: "evidential_layer", label: "Evidential Layer", type: .enum, required: true, autoFilled: false, description: "The represented content's evidential space.", allowedValues: DissertationControlV4.evidentialLayers.sorted()),
    FieldDefinition(key: "status", label: "Working Status", type: .enum, required: true, autoFilled: false, description: "Workflow state, not truth or publication status.", allowedValues: DissertationControlV4.statuses.sorted()),
    FieldDefinition(key: "settlement_dimensions", label: "Settlement Dimensions", type: .array, required: true, autoFilled: false, description: "Dimensions actually assessed.", allowedValues: DissertationControlV4.settlementDimensions.sorted()),
    FieldDefinition(key: "settlement_degree", label: "Settlement Degree", type: .enum, required: true, autoFilled: false, description: "Current degree of settlement.", allowedValues: DissertationControlV4.settlementDegrees.sorted()),
    FieldDefinition(key: "review_status", label: "Governance Review", type: .enum, required: true, autoFilled: false, description: "Human/agent review condition, separate from Scholium file review.", allowedValues: DissertationControlV4.reviewStatuses.sorted()),
    FieldDefinition(key: "confidence", label: "Working Confidence", type: .enum, required: true, autoFilled: false, description: "Qualitative only.", allowedValues: DissertationControlV4.confidences.sorted()),
    FieldDefinition(key: "evidence_state", label: "Evidence State", type: .enum, required: true, autoFilled: false, description: "Source-check condition; not a truth verdict.", allowedValues: DissertationControlV4.evidenceStates.sorted()),
    FieldDefinition(key: "prose_permission", label: "Prose Permission", type: .enum, required: true, autoFilled: false, description: "Whether and how draft prose may use this record.", allowedValues: DissertationControlV4.prosePermissions.sorted()),
    FieldDefinition(key: "privacy", label: "Privacy", type: .string, required: true, autoFilled: false, description: "Access scope; dissertation-original material remains local-only.", allowedValues: nil),
    FieldDefinition(key: "reopen_condition", label: "Reopen Condition", type: .text, required: true, autoFilled: false, description: "Condition requiring reconsideration.", allowedValues: nil),
    FieldDefinition(key: "provenance", label: "Provenance", type: .array, required: true, autoFilled: false, description: "Origins and authorizations; does not confer authority automatically.", allowedValues: nil),
    FieldDefinition(key: "created_at", label: "Created", type: .date, required: true, autoFilled: false, description: "Mechanical creation date.", allowedValues: nil),
    FieldDefinition(key: "updated_at", label: "Updated", type: .date, required: true, autoFilled: false, description: "Mechanical edit date; carries no review meaning.", allowedValues: nil),
    FieldDefinition(key: "last_reviewed", label: "Last Substantive Review", type: .date, required: true, autoFilled: false, description: "Changed only by explicit substantive review.", allowedValues: nil),
    FieldDefinition(key: "migration_state", label: "Migration State", type: .enum, required: false, autoFilled: false, description: "Only for migration and redirect records.", allowedValues: DissertationControlV4.migrationStates.sorted()),
    FieldDefinition(key: "question_kind", label: "Question Kind", type: .enum, required: false, autoFilled: false, description: "Required for question records.", allowedValues: DissertationControlV4.controlledFieldValues["question_kind"]?.sorted()),
    FieldDefinition(key: "claim_kind", label: "Claim Kind", type: .enum, required: false, autoFilled: false, description: "Required for claim records; premise and conclusion remain relations.", allowedValues: DissertationControlV4.controlledFieldValues["claim_kind"]?.sorted()),
    FieldDefinition(key: "inference_type", label: "Inference Type", type: .enum, required: false, autoFilled: false, description: "Required for inference records.", allowedValues: DissertationControlV4.controlledFieldValues["inference_type"]?.sorted()),
    FieldDefinition(key: "inference_force", label: "Inference Force", type: .enum, required: false, autoFilled: false, description: "Required for inference records; never a numerical weight.", allowedValues: DissertationControlV4.controlledFieldValues["inference_force"]?.sorted()),
    FieldDefinition(key: "position_kind", label: "Position Kind", type: .enum, required: false, autoFilled: false, description: "Required for position records.", allowedValues: DissertationControlV4.controlledFieldValues["position_kind"]?.sorted()),
    FieldDefinition(key: "concept_kind", label: "Concept Kind", type: .enum, required: false, autoFilled: false, description: "Required for concept records.", allowedValues: DissertationControlV4.controlledFieldValues["concept_kind"]?.sorted()),
    FieldDefinition(key: "case_kind", label: "Case Kind", type: .enum, required: false, autoFilled: false, description: "Counterexample force belongs in a relation.", allowedValues: DissertationControlV4.controlledFieldValues["case_kind"]?.sorted()),
    FieldDefinition(key: "evidence_kind", label: "Evidence Kind", type: .enum, required: false, autoFilled: false, description: "Required for evidence anchors.", allowedValues: DissertationControlV4.controlledFieldValues["evidence_kind"]?.sorted()),
    FieldDefinition(key: "verification_state", label: "Verification State", type: .enum, required: false, autoFilled: false, description: "Verification of the exact evidence anchor.", allowedValues: DissertationControlV4.controlledFieldValues["verification_state"]?.sorted()),
    FieldDefinition(key: "source_locator", label: "Source Locator", type: .string, required: false, autoFilled: false, description: "Exact source locator for an evidence anchor.", allowedValues: nil),
    FieldDefinition(key: "predicate", label: "Predicate", type: .enum, required: false, autoFilled: false, description: "Canonical represented predicate for a relation record.", allowedValues: DissertationControlV4.predicates.map(\.rawValue).sorted()),
    FieldDefinition(key: "semantic_direction", label: "Semantic Direction", type: .enum, required: false, autoFilled: false, description: "V4 relation records always run subject to object.", allowedValues: ["subject_to_object"]),
    FieldDefinition(key: "assembly_kind", label: "Assembly Kind", type: .enum, required: false, autoFilled: false, description: "Required for assembly maps.", allowedValues: DissertationControlV4.controlledFieldValues["assembly_kind"]?.sorted()),
    FieldDefinition(key: "chapter_id", label: "Chapter ID", type: .string, required: false, autoFilled: false, description: "Stable chapter code such as C01.", allowedValues: nil),
    FieldDefinition(key: "workflow_stage", label: "Workflow Stage", type: .enum, required: false, autoFilled: false, description: "Chapter-local workflow stage.", allowedValues: DissertationControlV4.controlledFieldValues["workflow_stage"]?.sorted()),
    FieldDefinition(key: "draft_target", label: "Draft Target", type: .string, required: false, autoFilled: false, description: "Existing draft path represented by a Draft Project bridge when external.", allowedValues: nil),
    FieldDefinition(key: "registry_kind", label: "Registry Kind", type: .enum, required: false, autoFilled: false, description: "Registries are derived views and never status authority.", allowedValues: DissertationControlV4.controlledFieldValues["registry_kind"]?.sorted()),
    FieldDefinition(key: "indexed_note_types", label: "Indexed Note Types", type: .array, required: false, autoFilled: false, description: "Controlled v4 note types mirrored by this registry.", allowedValues: DissertationControlV4.noteTypes.sorted()),
    FieldDefinition(key: "control_kind", label: "Control Kind", type: .enum, required: false, autoFilled: false, description: "Required for project-control records.", allowedValues: DissertationControlV4.controlledFieldValues["control_kind"]?.sorted()),
  ])

  static let generic = FrontmatterSchema(kb: .output, fields: [])

  static func schema(for kb: KnowledgeBase) -> FrontmatterSchema {
    switch kb {
    case .papers: return .papers
    case .topics: return .topics
    case .output: return .output
    }
  }

  static func schema(for note: Note) -> FrontmatterSchema {
    switch note.profile {
    case .paperAnalysis: return .papers
    case .topicKnowledge: return .topics
    case .dissertationControl:
      return note.frontmatter["schema_version"]?.stringValue == DissertationControlV4.schemaVersion
        ? .dissertationControlV4
        : .dissertationControl
    case .draftProject: return .output
    case .generic: return .generic
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

// MARK: - Search Result

struct SearchResult: Identifiable, Hashable {
  var id: String { notePath }
  let notePath: String
  let displayName: String
  let kb: KnowledgeBase
  let score: Double
  let matchField: String       // "title", "tag", "body", "authors"
  let snippet: String          // highlighted excerpt
  let highlights: [SearchHighlight]
  let sourceLine: Int
  let isReviewed: Bool
}
