import Foundation
import Markdown

public enum CritiqueStoreError: LocalizedError, Sendable {
    case unreadableStore(kind: String, reason: String)
    case restorationConflict(kind: String, identity: String)

    public var errorDescription: String? {
        switch self {
        case .unreadableStore(let kind, let reason):
            "Scholium could not safely load the \(kind) records. Their file was left unchanged. \(reason)"
        case .restorationConflict(let kind, let identity):
            "Scholium did not replace a concurrently changed \(kind) record during rollback: \(identity)"
        }
    }
}


public enum CritiqueFindingDispositionDecision: String, Codable, CaseIterable, Hashable, Sendable {
    case accept
    case reject
    case rebut
}

public struct CritiqueFindingDisposition: Codable, Hashable, Identifiable, Sendable {
    public var id: String { findingID }
    public let findingID: String
    public let decision: CritiqueFindingDispositionDecision
    public let rationale: String?
    /// Exact Work revision observed when an accepted finding was recorded
    /// after a text change. This does not claim which bytes addressed it.
    public let acceptedRevision: DocumentFingerprint?
    /// Researcher-authored explanation used only when Accept requires no text
    /// change. It is mutually exclusive with `acceptedRevision`.
    public let noTextChangeRationale: String?
    public let disposedAt: Date

    public init(
        findingID: String,
        decision: CritiqueFindingDispositionDecision,
        rationale: String? = nil,
        acceptedRevision: DocumentFingerprint? = nil,
        noTextChangeRationale: String? = nil,
        disposedAt: Date = Date()
    ) {
        self.findingID = findingID
        self.decision = decision
        let normalizedRationale = rationale?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rationale = normalizedRationale?.isEmpty == false ? normalizedRationale : nil
        self.acceptedRevision = acceptedRevision
        let normalizedNoChange = noTextChangeRationale?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.noTextChangeRationale = normalizedNoChange?.isEmpty == false
            ? normalizedNoChange
            : nil
        self.disposedAt = disposedAt
    }

    public var satisfiesRoundCompletion: Bool {
        switch decision {
        case .accept:
            (acceptedRevision != nil) != (noTextChangeRationale != nil)
        case .reject, .rebut:
            true
        }
    }
}

public struct CritiqueRound: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let requestedAt: Date
    public let targetFingerprint: DocumentFingerprint
    public let scope: CritiqueRequestScope
    public let actionableFindings: [CritiqueFinding]
    public let findingDispositions: [CritiqueFindingDisposition]
    public let completedAt: Date?

    public init(
        id: UUID = UUID(),
        requestedAt: Date = Date(),
        targetFingerprint: DocumentFingerprint,
        scope: CritiqueRequestScope,
        actionableFindings: [CritiqueFinding] = [],
        findingDispositions: [CritiqueFindingDisposition] = [],
        completedAt: Date? = nil
    ) {
        self.id = id
        self.requestedAt = requestedAt
        self.targetFingerprint = targetFingerprint
        self.scope = scope
        self.actionableFindings = Self.uniqueFindings(actionableFindings)
        let actionableIDs = Set(self.actionableFindings.map(\.id))
        self.findingDispositions = Dictionary(
            findingDispositions
                .filter { actionableIDs.contains($0.findingID) }
                .map { ($0.findingID, $0) },
            uniquingKeysWith: { _, newest in newest }
        ).values.sorted { $0.findingID < $1.findingID }
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, requestedAt, targetFingerprint, scope
        case actionableFindings
        case findingDispositions, completedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            requestedAt: try container.decode(Date.self, forKey: .requestedAt),
            targetFingerprint: try container.decode(
                DocumentFingerprint.self,
                forKey: .targetFingerprint
            ),
            scope: try container.decode(CritiqueRequestScope.self, forKey: .scope),
            actionableFindings: try container.decodeIfPresent(
                [CritiqueFinding].self,
                forKey: .actionableFindings
            ) ?? [],
            findingDispositions: try container.decodeIfPresent(
                [CritiqueFindingDisposition].self,
                forKey: .findingDispositions
            ) ?? [],
            completedAt: try container.decodeIfPresent(Date.self, forKey: .completedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(requestedAt, forKey: .requestedAt)
        try container.encode(targetFingerprint, forKey: .targetFingerprint)
        try container.encode(scope, forKey: .scope)
        if !actionableFindings.isEmpty {
            try container.encode(actionableFindings, forKey: .actionableFindings)
        }
        if !findingDispositions.isEmpty {
            try container.encode(findingDispositions, forKey: .findingDispositions)
        }
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }

    public var isReadyToComplete: Bool {
        guard completedAt == nil, !actionableFindings.isEmpty else { return false }
        let dispositions = Dictionary(
            uniqueKeysWithValues: findingDispositions.map { ($0.findingID, $0) }
        )
        return actionableFindings.allSatisfy {
            dispositions[$0.id]?.satisfiesRoundCompletion == true
        }
    }

    private static func uniqueFindings(_ findings: [CritiqueFinding]) -> [CritiqueFinding] {
        var seen: Set<String> = []
        return findings.filter { seen.insert($0.id).inserted }
    }
}

public struct CritiqueAssociation: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let workNoteID: UUID
    public var workRelativePath: String
    public var targetFingerprint: DocumentFingerprint
    public var critiqueRelativePath: String
    public let createdAt: Date
    public var updatedAt: Date
    public var rounds: [CritiqueRound]

    public init(
        id: UUID = UUID(),
        workNoteID: UUID,
        workRelativePath: String,
        targetFingerprint: DocumentFingerprint,
        critiqueRelativePath: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        rounds: [CritiqueRound] = []
    ) {
        self.id = id
        self.workNoteID = workNoteID
        self.workRelativePath = workRelativePath
        self.targetFingerprint = targetFingerprint
        self.critiqueRelativePath = critiqueRelativePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rounds = rounds
    }

    private enum CodingKeys: String, CodingKey {
        case id, workNoteID, workRelativePath, targetFingerprint
        case critiqueRelativePath, createdAt, updatedAt, rounds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workNoteID = try container.decode(UUID.self, forKey: .workNoteID)
        workRelativePath = try container.decode(String.self, forKey: .workRelativePath)
        targetFingerprint = try container.decode(DocumentFingerprint.self, forKey: .targetFingerprint)
        critiqueRelativePath = try container.decode(String.self, forKey: .critiqueRelativePath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        rounds = try container.decodeIfPresent([CritiqueRound].self, forKey: .rounds) ?? []
    }
}

public enum CritiqueRequestScope: String, Codable, CaseIterable, Sendable {
    case overall = "Overall Critique"
    case specific = "Specific Comments"
    case both = "Both"
}

public struct CritiquePromptContext: Sendable {
    public let template: String
    public let scope: CritiqueRequestScope
    public let lens: String
    public let selectedRanges: String
    public let additionalInstructions: String
    public let workTitle: String
    public let workRelativePath: String
    public let workFingerprint: DocumentFingerprint
    public let critiqueRelativePath: String

    public init(
        template: String,
        scope: CritiqueRequestScope,
        lens: String = "",
        selectedRanges: String = "",
        additionalInstructions: String = "",
        workTitle: String,
        workRelativePath: String,
        workFingerprint: DocumentFingerprint,
        critiqueRelativePath: String
    ) {
        self.template = template
        self.scope = scope
        self.lens = lens
        self.selectedRanges = selectedRanges
        self.additionalInstructions = additionalInstructions
        self.workTitle = workTitle
        self.workRelativePath = workRelativePath
        self.workFingerprint = workFingerprint
        self.critiqueRelativePath = critiqueRelativePath
    }
}

public enum CritiquePromptBuilder {
    public static func build(_ context: CritiquePromptContext) -> String {
        let replacements = [
            "{{critique_scope}}": context.scope.rawValue,
            "{{critique_lens}}": context.lens.isEmpty ? "No additional lens specified" : context.lens,
            "{{selected_ranges}}": context.selectedRanges.isEmpty ? "No passage specified" : context.selectedRanges,
            "{{additional_instructions}}": context.additionalInstructions.isEmpty
                ? "No additional instructions"
                : context.additionalInstructions,
        ]
        var body = context.template
        for (placeholder, value) in replacements {
            body = body.replacingOccurrences(of: placeholder, with: value)
        }
        return [
            "Scholium Critique request",
            "Target Work: \(context.workTitle)",
            "Target path: \(context.workRelativePath)",
            "Target advisory SHA-256: \(context.workFingerprint.sha256)",
            "Write Critique to: \(context.critiqueRelativePath)",
            "Keep critique_authorship as agent, critique_target_path as \(context.workRelativePath), and critique_target_fingerprint as \(context.workFingerprint.sha256).",
            "Under Specific Findings, give each finding a level-three heading and the fields Target Work, Target fingerprint, Target heading or Target line, and Target quotation when available.",
            "",
            body,
        ].joined(separator: "\n")
    }
}

public enum CritiquePlacementError: LocalizedError, Sendable {
    case invalidCritiquePath(String)
    case crossesCritiqueBoundary(source: String, destination: String)
    case directCreationRequiresRequestCritique
    case duplicateNotSupported
    case malformedFrontmatter

    public var errorDescription: String? {
        switch self {
        case .invalidCritiquePath(let path):
            "A Critique must remain inside the Works/Critiques folder: \(path)"
        case .crossesCritiqueBoundary(let source, let destination):
            "Scholium cannot move a Critique outside Works/Critiques or turn an ordinary Work into a Critique by moving it there. Move within Critiques or cancel. (\(source) → \(destination))"
        case .directCreationRequiresRequestCritique:
            "Use Request Critique on a Work to create its associated Critique."
        case .duplicateNotSupported:
            "A Work has at most one current Critique. Request another Critique round instead of duplicating the Critique document."
        case .malformedFrontmatter:
            "The existing Critique begins with malformed or unterminated YAML. Repair it in an external editor before requesting another round."
        }
    }
}

public enum CritiquePlacement {
    public static func isActiveCritiquePath(_ relativePath: String) -> Bool {
        return relativePath.hasPrefix("Critiques/")
            && relativePath.lowercased().hasSuffix(".md")
            && !relativePath.dropFirst("Critiques/".count).isEmpty
    }

    public static func isManagedCritiquePath(_ relativePath: String) -> Bool {
        isActiveCritiquePath(relativePath)
    }

    public static func validateOrdinaryMove(from source: String, to destination: String) throws {
        let sourceIsCritique = isManagedCritiquePath(source)
        let destinationIsCritique = isManagedCritiquePath(destination)
        guard sourceIsCritique == destinationIsCritique else {
            throw CritiquePlacementError.crossesCritiqueBoundary(source: source, destination: destination)
        }
    }
}

public struct CritiqueDocumentMetadata: Codable, Hashable, Sendable {
    public let authorship: String?
    public let targetRelativePath: String?
    public let targetFingerprintSHA256: String?
    public let requestedAt: Date?
    public let scope: CritiqueRequestScope?

    public var isAgentAttributed: Bool {
        authorship?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("agent") == .orderedSame
    }
}

public enum CritiqueFindingJudgment: String, Codable, Hashable, Sendable {
    case traced = "Traced"
    case untraced = "Untraced"
    case disputed = "Disputed"
    case beyondSources = "Beyond Sources"
    case unspecified = "Finding"
}

public struct CritiqueFinding: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(critiqueSourceLine):\(title)" }
    public let judgment: CritiqueFindingJudgment
    public let title: String
    public let critiqueSourceLine: Int
    public let targetRelativePath: String?
    public let targetFingerprintSHA256: String?
    public let targetHeading: String?
    public let targetLine: Int?
    public let targetQuotation: String?

    public init(
        judgment: CritiqueFindingJudgment,
        title: String,
        critiqueSourceLine: Int,
        targetRelativePath: String? = nil,
        targetFingerprintSHA256: String? = nil,
        targetHeading: String? = nil,
        targetLine: Int? = nil,
        targetQuotation: String? = nil
    ) {
        self.judgment = judgment
        self.title = title
        self.critiqueSourceLine = critiqueSourceLine
        self.targetRelativePath = targetRelativePath
        self.targetFingerprintSHA256 = targetFingerprintSHA256
        self.targetHeading = targetHeading
        self.targetLine = targetLine
        self.targetQuotation = targetQuotation
    }

    /// Resolves only explicit source information. Ambiguous quotations never
    /// select an arbitrary occurrence.
    public func resolvedTargetLine(in document: NoteDocument) -> Int? {
        if let targetLine,
           targetLine > 0,
           targetLine <= document.rawContent.components(separatedBy: .newlines).count {
            return targetLine
        }
        if let targetHeading {
            let matching = MarkdownSemanticDocument(parsing: document).headings.filter {
                $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(targetHeading.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            }
            if matching.count == 1 { return matching[0].span.start.line }
        }
        if let targetQuotation, !targetQuotation.isEmpty {
            var ranges: [Range<String.Index>] = []
            var searchStart = document.rawContent.startIndex
            while searchStart < document.rawContent.endIndex,
                  let range = document.rawContent.range(of: targetQuotation, range: searchStart..<document.rawContent.endIndex) {
                ranges.append(range)
                searchStart = range.upperBound
            }
            if ranges.count == 1 {
                return document.rawContent[..<ranges[0].lowerBound].reduce(1) { count, character in
                    character == "\n" ? count + 1 : count
                }
            }
        }
        return nil
    }
}

public enum CritiqueDocumentContract {
    public static let authorshipKey = "critique_authorship"
    public static let targetPathKey = "critique_target_path"
    public static let targetFingerprintKey = "critique_target_fingerprint"
    public static let requestedAtKey = "critique_requested_at"
    public static let requestScopeKey = "critique_request_scope"

    public static func scaffold(
        title: String,
        targetRelativePath: String,
        targetFingerprint: DocumentFingerprint,
        scope: CritiqueRequestScope,
        requestedAt: Date = Date()
    ) -> String {
        let timestamp = timestampString(requestedAt)
        let headingTitle = title
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return """
        ---
        \(authorshipKey): agent
        \(targetPathKey): \(quoted(targetRelativePath))
        \(targetFingerprintKey): \(targetFingerprint.sha256)
        \(requestedAtKey): \(quoted(timestamp))
        \(requestScopeKey): \(quoted(scope.rawValue))
        ---
        # Critique: \(headingTitle)

        ## Overall Assessment

        ## Strengths

        ## Major Concerns

        ## Source Support

        ## Objections and Alternatives

        ## Revision Priorities

        ## Specific Findings

        <!-- For each finding, use a level-three heading and list Target Work,
        Target fingerprint, Target heading or Target line, and Target quotation
        when available. Scholium uses those explicit fields for source navigation. -->

        ## Evidence Limits
        """ + "\n"
    }

    public static func requestEdits(
        targetRelativePath: String,
        targetFingerprint: DocumentFingerprint,
        scope: CritiqueRequestScope,
        requestedAt: Date = Date()
    ) -> [String: FrontmatterEditValue] {
        [
            authorshipKey: .string("agent"),
            targetPathKey: .string(targetRelativePath),
            targetFingerprintKey: .string(targetFingerprint.sha256),
            requestedAtKey: .string(timestampString(requestedAt)),
            requestScopeKey: .string(scope.rawValue),
        ]
    }

    /// Adds a new metadata block to a Critique that has no frontmatter,
    /// preserving every existing source byte after the optional BOM.
    public static func sourceByAddingRequestMetadata(
        to document: NoteDocument,
        targetRelativePath: String,
        targetFingerprint: DocumentFingerprint,
        scope: CritiqueRequestScope,
        requestedAt: Date = Date()
    ) throws -> String {
        guard document.rawFrontmatter == nil else { return document.rawContent }
        var existing = document.rawContent
        let bom: String
        if existing.unicodeScalars.first?.value == 0xFEFF {
            bom = "\u{FEFF}"
            existing.removeFirst()
        } else {
            bom = ""
        }
        let firstLine = existing.split(whereSeparator: \.isNewline)
            .first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard firstLine != "---" else {
            throw CritiquePlacementError.malformedFrontmatter
        }
        let newline = document.newlineStyle.sequence
        let orderedKeys = [authorshipKey, targetPathKey, targetFingerprintKey, requestedAtKey, requestScopeKey]
        let values: [String: String] = [
            authorshipKey: "agent",
            targetPathKey: quoted(targetRelativePath),
            targetFingerprintKey: targetFingerprint.sha256,
            requestedAtKey: quoted(timestampString(requestedAt)),
            requestScopeKey: quoted(scope.rawValue),
        ]
        let frontmatter = (["---"] + orderedKeys.compactMap { key in
            values[key].map { "\(key): \($0)" }
        } + ["---", ""]).joined(separator: newline)
        return bom + frontmatter + existing
    }

    public static func metadata(in document: NoteDocument) -> CritiqueDocumentMetadata {
        let values = document.parsedFrontmatter
        let fingerprint: String?
        if let sha = values[targetFingerprintKey]?.scalarString,
           sha.count == 64,
           sha.allSatisfy({ $0.isHexDigit }) {
            fingerprint = sha.lowercased()
        } else {
            fingerprint = nil
        }
        let scope = values[requestScopeKey]?.scalarString.flatMap(CritiqueRequestScope.init(rawValue:))
        let requestedAt = values[requestedAtKey]?.scalarString.flatMap(timestampDate)
        return CritiqueDocumentMetadata(
            authorship: values[authorshipKey]?.scalarString,
            targetRelativePath: values[targetPathKey]?.scalarString,
            targetFingerprintSHA256: fingerprint,
            requestedAt: requestedAt,
            scope: scope
        )
    }

    public static func findings(in document: NoteDocument) -> [CritiqueFinding] {
        let metadata = metadata(in: document)
        let lines = document.rawContent.components(separatedBy: .newlines)
        var inSpecificFindings = false
        var inFence = false
        var current: FindingBuilder?
        var result: [CritiqueFinding] = []

        func finish(_ builder: FindingBuilder?) -> CritiqueFinding? {
            guard let builder,
                  builder.targetLine != nil || builder.targetHeading != nil || builder.targetQuotation != nil else {
                return nil
            }
            return builder.build(defaultMetadata: metadata)
        }

        for (offset, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            if line.hasPrefix("## ") && !line.hasPrefix("### ") {
                if let finding = finish(current) { result.append(finding) }
                current = nil
                inSpecificFindings = String(line.dropFirst(3))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("Specific Findings") == .orderedSame
                continue
            }
            guard inSpecificFindings else { continue }
            if line.hasPrefix("### ") {
                if let finding = finish(current) { result.append(finding) }
                current = FindingBuilder(heading: String(line.dropFirst(4)), sourceLine: offset + 1)
                continue
            }
            guard var builder = current,
                  let pair = labelledValue(in: line) else { continue }
            builder.consume(label: pair.label, value: pair.value)
            current = builder
        }
        if let finding = finish(current) { result.append(finding) }
        return result
    }

    private struct FindingBuilder {
        let judgment: CritiqueFindingJudgment
        let title: String
        let sourceLine: Int
        var targetRelativePath: String?
        var targetFingerprintSHA256: String?
        var targetHeading: String?
        var targetLine: Int?
        var targetQuotation: String?

        init(heading: String, sourceLine: Int) {
            let cleaned = clean(heading)
            let lower = cleaned.lowercased()
            let matched: (CritiqueFindingJudgment, String)? = [
                (.beyondSources, "beyond sources"),
                (.untraced, "untraced"),
                (.disputed, "disputed"),
                (.traced, "traced"),
            ].first { lower.hasPrefix($0.1) }
            judgment = matched?.0 ?? .unspecified
            if let (matchedJudgment, prefix) = matched {
                var remainder = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " :—–-"))
                if remainder.isEmpty { remainder = matchedJudgment.rawValue }
                title = remainder
            } else {
                title = cleaned.isEmpty ? CritiqueFindingJudgment.unspecified.rawValue : cleaned
            }
            self.sourceLine = sourceLine
        }

        mutating func consume(label: String, value: String) {
            switch normalized(label) {
            case "target", "targetwork", "targetpath", "work": targetRelativePath = clean(value)
            case "targetfingerprint", "fingerprint", "targetsha256", "sha256":
                let sha = clean(value).lowercased()
                if sha.count == 64, sha.allSatisfy({ $0.isHexDigit }) {
                    targetFingerprintSHA256 = sha
                }
            case "targetheading", "heading", "section": targetHeading = clean(value)
            case "targetline", "line", "originalline":
                targetLine = clean(value).split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first
            case "targetquotation", "quotation", "quote": targetQuotation = clean(value)
            default: break
            }
        }

        func build(defaultMetadata: CritiqueDocumentMetadata) -> CritiqueFinding {
            CritiqueFinding(
                judgment: judgment,
                title: title,
                critiqueSourceLine: sourceLine,
                targetRelativePath: targetRelativePath ?? defaultMetadata.targetRelativePath,
                targetFingerprintSHA256: targetFingerprintSHA256 ?? defaultMetadata.targetFingerprintSHA256,
                targetHeading: targetHeading,
                targetLine: targetLine,
                targetQuotation: targetQuotation
            )
        }
    }

    private static func labelledValue(in line: String) -> (label: String, value: String)? {
        var value = line
        if value.hasPrefix("-") || value.hasPrefix("*") { value.removeFirst() }
        value = value.trimmingCharacters(in: .whitespaces)
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let label = clean(String(value[..<colon]))
        let content = clean(String(value[value.index(after: colon)...]))
        guard !label.isEmpty, !content.isEmpty else { return nil }
        return (label, content)
    }

    private static func normalized(_ value: String) -> String {
        clean(value).lowercased().filter(\.isLetter)
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "`*_“”\"")))
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func timestampDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}

public enum CritiqueRegistryError: LocalizedError, Sendable {
    case destinationAlreadyAssociated(String)
    case workPathMismatch(expected: String, actual: String)
    case roundNotFound(UUID)
    case roundNotReady(UUID)
    case roundAlreadyCompleted(UUID)
    case findingSetAlreadyCaptured(UUID)
    case findingNotFound(String)
    case acceptRequiresChangeOrRationale(String)
    case incompleteDispositions(UUID)

    public var errorDescription: String? {
        switch self {
        case .destinationAlreadyAssociated(let path):
            "The Critique at \(path) is already associated with another Work."
        case .workPathMismatch(let expected, let actual):
            "The Critique association expected its Work at \(expected), but it currently records \(actual)."
        case .roundNotFound(let id):
            "Critique round was not found: \(id.uuidString)"
        case .roundNotReady(let id):
            "Critique round is not ready for finding disposition: \(id.uuidString)"
        case .roundAlreadyCompleted(let id):
            "Critique round is already complete: \(id.uuidString)"
        case .findingSetAlreadyCaptured(let id):
            "The actionable finding set is already fixed for Critique round \(id.uuidString)."
        case .findingNotFound(let id):
            "Critique finding was not found in the fixed round: \(id)"
        case .acceptRequiresChangeOrRationale(let id):
            "Accept requires a changed Work revision or an explicit no-text-change rationale for finding \(id)."
        case .incompleteDispositions(let id):
            "Every actionable finding must be disposed before completing Critique round \(id.uuidString)."
        }
    }
}
