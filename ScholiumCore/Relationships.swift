import CryptoKit
import Foundation

public enum RelationshipPredicate: String, Codable, CaseIterable, Sendable {
    case supports
    case contradicts
    case extends
    case refines
    case questions
    case incompatibleWith = "incompatible_with"
    case cites
    case seeAlso = "see-also"
    case connected
    case answers
    case subquestionOf = "subquestion_of"
    case premiseOf = "premise_of"
    case concludes
    case assumes
    case pressures
    case usesConcept = "uses_concept"
    case hasCommitment = "has_commitment"
    case targets
    case objectsTo = "objects_to"
    case rebuts
    case undercuts
    case repliesTo = "replies_to"
    case concedes
    case dependsOn = "depends_on"
    case supersedes
    case qualifies
    case elicits
    case tests
    case illustrates
    case counterexampleTo = "counterexample_to"
    case evidenceFor = "evidence_for"
    case attributesTo = "attributes_to"
    case interprets
    case derivedFrom = "derived_from"
    case isCaseFor = "is_case_for"
    case isSourceFor = "is_source_for"
    case isBackgroundFor = "is_background_for"
    case isNotEvidenceFor = "is_not_evidence_for"

    public var category: RelationshipCategory {
        switch self {
        case .seeAlso, .connected: .navigation
        case .cites: .citation
        case .evidenceFor, .isCaseFor, .isSourceFor, .isBackgroundFor, .isNotEvidenceFor: .evidence
        case .supports, .contradicts, .extends, .refines, .questions, .incompatibleWith, .pressures, .targets,
             .objectsTo, .rebuts, .undercuts, .repliesTo, .concedes, .qualifies,
             .elicits, .tests, .illustrates, .counterexampleTo, .attributesTo, .interprets: .argument
        case .supersedes, .derivedFrom: .revision
        case .answers, .subquestionOf, .premiseOf, .concludes, .assumes, .usesConcept,
             .hasCommitment, .dependsOn: .governance
        }
    }

    public var directionConvention: RelationshipDirectionConvention {
        switch self {
        case .supports, .contradicts, .extends, .refines, .questions:
            .targetActsOnContaining
        case .seeAlso, .connected, .incompatibleWith:
            .undirected
        default:
            .containingActsOnTarget
        }
    }

    public var conveysPositiveEvidence: Bool {
        switch self {
        case .evidenceFor, .isCaseFor, .isSourceFor: true
        default: false
        }
    }

    public var requiresGovernanceAttention: Bool {
        category == .revision || category == .governance || self == .isNotEvidenceFor
    }

    public var isSubstantive: Bool {
        category != .navigation
    }
}

public enum RelationshipCategory: String, Codable, CaseIterable, Sendable {
    case navigation
    case citation
    case evidence
    case argument
    case revision
    case governance
}

public enum RelationshipDirectionConvention: String, Codable, Sendable {
    case targetActsOnContaining
    case containingActsOnTarget
    case undirected
}

public enum RelationshipResolution: Codable, Hashable, Sendable {
    case resolved(String)
    case ambiguous([String])
    case broken(String)
}

public struct SourceLocator: Codable, Hashable, Sendable {
    public let file: String
    public let line: Int
    public let column: Int
    public let headingOrBlock: String?

    public init(file: String, line: Int, column: Int, headingOrBlock: String? = nil) {
        self.file = file
        self.line = line
        self.column = column
        self.headingOrBlock = headingOrBlock
    }
}

public struct RelationshipSourceOccurrence: Codable, Hashable, Sendable {
    public let locator: SourceLocator
    public let syntax: LinkSyntax
    public let vectorKind: VectorLinkKind?

    public init(locator: SourceLocator, syntax: LinkSyntax, vectorKind: VectorLinkKind?) {
        self.locator = locator
        self.syntax = syntax
        self.vectorKind = vectorKind
    }
}

public struct RelationshipEdge: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    /// Vault-qualified endpoints are authoritative whenever resolution
    /// succeeded. The path-only fields remain for display and decoding older
    /// derived snapshots; they are never sufficient to identify a Triptych
    /// note when two vaults contain the same relative path.
    public let subjectNote: VaultQualifiedNoteID?
    public let subjectPath: String
    public let predicate: RelationshipPredicate
    public let objectNote: VaultQualifiedNoteID?
    public let objectPath: String
    public let locator: SourceLocator
    public let resolution: RelationshipResolution
    public let isExplicit: Bool
    public let isDirectional: Bool
    public let vectorKind: VectorLinkKind?
    public let occurrences: [RelationshipSourceOccurrence]

    public init(
        id: UUID? = nil,
        subjectNote: VaultQualifiedNoteID? = nil,
        subjectPath: String,
        predicate: RelationshipPredicate,
        objectNote: VaultQualifiedNoteID? = nil,
        objectPath: String,
        locator: SourceLocator,
        resolution: RelationshipResolution,
        isExplicit: Bool,
        isDirectional: Bool,
        vectorKind: VectorLinkKind? = nil,
        occurrences: [RelationshipSourceOccurrence] = []
    ) {
        self.id = id ?? Self.stableID(
            subjectNote: subjectNote,
            subjectPath: subjectPath,
            predicate: predicate,
            objectNote: objectNote,
            objectPath: objectPath,
            locator: locator
        )
        self.subjectNote = subjectNote
        self.subjectPath = subjectPath
        self.predicate = predicate
        self.objectNote = objectNote
        self.objectPath = objectPath
        self.locator = locator
        self.resolution = resolution
        self.isExplicit = isExplicit
        self.isDirectional = isDirectional
        self.vectorKind = vectorKind
        self.occurrences = occurrences
    }

    private static func stableID(
        subjectNote: VaultQualifiedNoteID?,
        subjectPath: String,
        predicate: RelationshipPredicate,
        objectNote: VaultQualifiedNoteID?,
        objectPath: String,
        locator: SourceLocator
    ) -> UUID {
        let seed = [
            subjectNote.map { "\($0.vaultID.uuidString.lowercased()):\($0.relativePath)" } ?? subjectPath,
            predicate.rawValue,
            objectNote.map { "\($0.vaultID.uuidString.lowercased()):\($0.relativePath)" } ?? objectPath,
            locator.file,
            String(locator.line),
            String(locator.column),
        ]
            .joined(separator: "\u{1F}")
        var hexadecimal = Array(SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32))
        hexadecimal[12] = "5"
        hexadecimal[16] = "8"
        let value = String(hexadecimal[0..<8]) + "-" + String(hexadecimal[8..<12]) + "-"
            + String(hexadecimal[12..<16]) + "-" + String(hexadecimal[16..<20]) + "-"
            + String(hexadecimal[20..<32])
        return UUID(uuidString: value)!
    }

    private static func vectorStableID(
        subject: VaultQualifiedNoteID?,
        subjectPath: String,
        predicate: RelationshipPredicate,
        object: VaultQualifiedNoteID?,
        objectPath: String
    ) -> UUID {
        let seed = [
            subject.map { "\($0.vaultID.uuidString.lowercased()):\($0.relativePath)" } ?? subjectPath,
            predicate.rawValue,
            object.map { "\($0.vaultID.uuidString.lowercased()):\($0.relativePath)" } ?? objectPath,
        ]
            .joined(separator: "\u{1F}")
        var hexadecimal = Array(SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32))
        hexadecimal[12] = "5"
        hexadecimal[16] = "8"
        let value = String(hexadecimal[0..<8]) + "-" + String(hexadecimal[8..<12]) + "-"
            + String(hexadecimal[12..<16]) + "-" + String(hexadecimal[16..<20]) + "-"
            + String(hexadecimal[20..<32])
        return UUID(uuidString: value)!
    }

    public static func vector(
        containing: VaultQualifiedNoteID,
        target: VaultQualifiedNoteID?,
        targetPath: String,
        kind: VectorLinkKind,
        locator: SourceLocator,
        syntax: LinkSyntax,
        resolution: RelationshipResolution
    ) -> RelationshipEdge {
        let subject: String
        let object: String
        let subjectNote: VaultQualifiedNoteID?
        let objectNote: VaultQualifiedNoteID?
        let predicate: RelationshipPredicate
        let directional: Bool
        let explicit: Bool
        switch kind {
        case .neutral:
            if let target, target < containing {
                subject = target.relativePath
                subjectNote = target
                object = containing.relativePath
                objectNote = containing
            } else {
                subject = containing.relativePath
                subjectNote = containing
                object = targetPath
                objectNote = target
            }
            predicate = .connected
            directional = false
            explicit = false
        case .supportsTarget:
            subject = containing.relativePath
            subjectNote = containing
            object = targetPath
            objectNote = target
            predicate = .supports
            directional = true
            explicit = true
        case .supportedByTarget:
            subject = targetPath
            subjectNote = target
            object = containing.relativePath
            objectNote = containing
            predicate = .supports
            directional = true
            explicit = true
        case .incompatible:
            if let target, target < containing {
                subject = target.relativePath
                subjectNote = target
                object = containing.relativePath
                objectNote = containing
            } else {
                subject = containing.relativePath
                subjectNote = containing
                object = targetPath
                objectNote = target
            }
            predicate = .incompatibleWith
            directional = false
            explicit = true
        }
        let normalizedResolution: RelationshipResolution
        switch resolution {
        case .resolved:
            normalizedResolution = .resolved(object)
        case .ambiguous(let candidates):
            normalizedResolution = .ambiguous(candidates)
        case .broken(let target):
            normalizedResolution = .broken(target)
        }
        return RelationshipEdge(
            id: vectorStableID(
                subject: subjectNote,
                subjectPath: subject,
                predicate: predicate,
                object: objectNote,
                objectPath: object
            ),
            subjectNote: subjectNote,
            subjectPath: subject,
            predicate: predicate,
            objectNote: objectNote,
            objectPath: object,
            locator: locator,
            resolution: normalizedResolution,
            isExplicit: explicit,
            isDirectional: directional,
            vectorKind: kind,
            occurrences: [RelationshipSourceOccurrence(locator: locator, syntax: syntax, vectorKind: kind)]
        )
    }

    public func mergingOccurrences(from other: RelationshipEdge) -> RelationshipEdge {
        let merged = Array(Set(occurrences + other.occurrences)).sorted {
            if $0.locator.file != $1.locator.file { return $0.locator.file < $1.locator.file }
            if $0.locator.line != $1.locator.line { return $0.locator.line < $1.locator.line }
            return $0.locator.column < $1.locator.column
        }
        return RelationshipEdge(
            id: id,
            subjectNote: subjectNote,
            subjectPath: subjectPath,
            predicate: predicate,
            objectNote: objectNote,
            objectPath: objectPath,
            locator: merged.first?.locator ?? locator,
            resolution: resolution,
            isExplicit: isExplicit,
            isDirectional: isDirectional,
            vectorKind: vectorKind,
            occurrences: merged
        )
    }

    /// Normalizes legacy typed-wikilink shorthand into a philosophical proposition.
    /// Vector-Link v1 uses ``vector(vaultID:containingPath:targetPath:kind:locator:syntax:resolution:)``.
    public static func explicit(
        containingPath: String,
        targetPath: String,
        predicate: RelationshipPredicate,
        locator: SourceLocator,
        resolution: RelationshipResolution
    ) -> RelationshipEdge {
        switch predicate.directionConvention {
        case .containingActsOnTarget:
            return RelationshipEdge(
                subjectPath: containingPath,
                predicate: predicate,
                objectPath: targetPath,
                locator: locator,
                resolution: resolution,
                isExplicit: true,
                isDirectional: true
            )
        case .undirected:
            return RelationshipEdge(
                subjectPath: containingPath,
                predicate: predicate,
                objectPath: targetPath,
                locator: locator,
                resolution: resolution,
                isExplicit: predicate != .connected,
                isDirectional: false
            )
        case .targetActsOnContaining:
            return RelationshipEdge(
                subjectPath: targetPath,
                predicate: predicate,
                objectPath: containingPath,
                locator: locator,
                resolution: resolution,
                isExplicit: true,
                isDirectional: true
            )
        }
    }
}

public struct RelationshipTrace: Codable, Hashable, Sendable {
    public let edges: [RelationshipEdge]
    public let isDirect: Bool
    public let classification: RelationshipTraceClassification

    public init(edges: [RelationshipEdge]) {
        self.edges = edges
        self.isDirect = edges.count == 1
        if edges.count > 1 {
            classification = .connectionPath
        } else if let edge = edges.first, edge.isExplicit, edge.predicate.isSubstantive {
            classification = .explicitAssertion
        } else {
            classification = .directConnection
        }
    }

    /// A multi-hop trace is a connection path only. It never inherits a
    /// substantive predicate from one of its component edges.
    public var assertedPredicate: RelationshipPredicate? {
        classification == .explicitAssertion ? edges.first?.predicate : nil
    }
}

public enum RelationshipTraceClassification: String, Codable, Hashable, Sendable {
    case explicitAssertion = "explicit_assertion"
    case directConnection = "direct_connection"
    case connectionPath = "connection_path"
}
