import Foundation

/// Machine-readable projection of the Dissertation Control Vault v4 contract.
/// It validates declared structure; it does not decide philosophical truth,
/// evidential sufficiency, or whether a researcher should approve a record.
public enum DissertationControlV4 {
    public static let schemaVersion = "dissertation-control-v4"

    public static let noteTypes: Set<String> = [
        "question", "claim", "inference", "position", "concept", "case",
        "evidence_anchor", "relation_record", "assembly_map", "chapter_dossier",
        "draft_interface", "registry", "project_control",
    ]
    public static let projectRoles: Set<String> = [
        "atomic_content", "relation_control", "assembly", "chapter_control",
        "draft_control", "registry", "entrypoint", "control_spec", "contract",
        "workflow_protocol", "project_control", "template", "archive",
    ]
    public static let origins: Set<String> = ["researcher", "source", "opponent", "agent_reconstruction"]
    public static let evidentialLayers: Set<String> = [
        "primary_source", "paper_analysis", "topic_note", "dissertation_record",
        "draft_prose", "agent_reconstruction",
    ]
    public static let statuses: Set<String> = [
        "open", "exploratory", "candidate", "provisional", "anchored", "tested",
        "chapter_ready", "draft_locked", "committee_tested", "submission_ready",
    ]
    public static let settlementDimensions: Set<String> = [
        "textual", "interpretive", "conceptual", "inferential", "dialectical",
        "comparative", "chapter_practical", "supervisor_committee", "submission",
    ]
    public static let settlementDegrees: Set<String> = [
        "open", "exploratory", "candidate", "provisional", "textually_anchored",
        "conceptually_controlled", "inferentially_reconstructed", "dialectically_tested",
        "relation_ready", "chapter_ready", "draft_locked", "committee_tested", "submission_ready",
    ]
    public static let reviewStatuses: Set<String> = [
        "agent_proposed", "researcher_review_required", "accepted_provisionally",
        "researcher_revised", "rejected", "approved",
    ]
    public static let reviewedStatuses: Set<String> = ["accepted_provisionally", "researcher_revised", "approved"]
    public static let confidences: Set<String> = ["low", "medium", "high"]
    public static let evidenceStates: Set<String> = [
        "not_applicable", "unverified", "needs_source_check", "partly_supported", "source_checked", "disputed",
    ]
    public static let prosePermissions: Set<String> = ["no", "not_yet", "footnote_only", "background_only", "yes_with_caution", "yes"]
    public static let positiveProsePermissions: Set<String> = ["footnote_only", "background_only", "yes_with_caution", "yes"]
    public static let migrationStates: Set<String> = ["legacy", "extracting", "atomic_canonical", "assembly_canonical", "redirect"]

    public static let commonRequiredFields = [
        "schema_version", "note_id", "title", "note_type", "project_role", "origin",
        "evidential_layer", "status", "settlement_dimensions", "settlement_degree",
        "review_status", "confidence", "evidence_state", "prose_permission", "privacy",
        "created_at", "updated_at", "last_reviewed", "reopen_condition", "provenance",
    ]

    public static let additionalRequiredFields: [String: [String]] = [
        "question": ["question_kind"], "claim": ["claim_kind"],
        "inference": ["inference_type", "inference_force"], "position": ["position_kind"],
        "concept": ["concept_kind"], "case": ["case_kind"],
        "evidence_anchor": ["evidence_kind", "verification_state", "source_locator"],
        "relation_record": ["predicate", "semantic_direction"],
        "assembly_map": ["assembly_kind"], "chapter_dossier": ["chapter_id", "workflow_stage"],
        "draft_interface": ["draft_target"], "registry": ["registry_kind", "indexed_note_types"],
        "project_control": ["control_kind"],
    ]

    public static let controlledFieldValues: [String: Set<String>] = [
        "question_kind": ["core", "subquestion", "methodological", "interpretive", "diagnostic", "other"],
        "claim_kind": ["project", "definition", "distinction", "scope", "source_attribution", "interpretation", "case_judgment", "empirical", "phenomenological", "methodological", "concession", "qualification", "other"],
        "inference_type": ["deductive", "inductive", "abductive", "conceptual", "analogical", "transcendental", "practical", "other"],
        "inference_force": ["entails", "strong_support", "pro_tanto", "best_explanation", "diagnostic", "illustrative", "open"],
        "position_kind": ["project", "opponent", "source_account", "methodological", "other"],
        "concept_kind": ["concept", "term", "family", "other"],
        "case_kind": ["thought_experiment", "actual_case", "example", "analogy", "limiting_case", "other"],
        "evidence_kind": ["primary_passage", "quotation", "empirical_result", "historical_datum", "phenomenological_report", "linguistic_datum", "citation_record", "source_control", "other"],
        "verification_state": ["unverified", "partly_verified", "verified", "disputed"],
        "semantic_direction": ["subject_to_object"],
        "assembly_kind": ["dissertation_spine", "argument_map", "dialectic_map", "concept_map", "other"],
        "workflow_stage": ["not started", "notes gathered", "concepts clarified", "source map integrated", "objections mapped", "literature integrated", "rough prose", "structural revision", "advisor-ready", "feedback received", "revision completed", "committee-ready", "final harmonization", "submission-ready"],
        "registry_kind": ["index", "review_entrypoint", "review_queue", "migration_manifest", "migration_review", "deployment_acceptance", "chapter_registry", "claim_registry", "argument_registry", "concept_registry", "position_relation_registry", "source_control_registry", "archive_registry", "other"],
        "control_kind": ["operating_specification", "folder_role_contract", "relation_direction_contract", "property_glossary", "atomicity_criterion", "workflow", "entrypoint", "architecture_summary", "template", "redirect", "other"],
    ]

    public static let advancedStatuses: Set<String> = ["anchored", "tested", "chapter_ready", "draft_locked", "committee_tested", "submission_ready"]
    public static let predicates: Set<RelationshipPredicate> = [
        .answers, .subquestionOf, .premiseOf, .concludes, .assumes, .dependsOn, .usesConcept, .hasCommitment,
        .targets, .supports, .objectsTo, .rebuts, .undercuts, .pressures, .repliesTo, .concedes, .qualifies, .contradicts,
        .elicits, .tests, .illustrates, .counterexampleTo, .evidenceFor, .attributesTo, .interprets,
        .isBackgroundFor, .isNotEvidenceFor, .derivedFrom, .supersedes,
    ]

    public static func permits(predicate: RelationshipPredicate, subject: String, object: String) -> Bool {
        let map = "assembly_map"
        let relation = "relation_record"
        let all = noteTypes
        let substantive = noteTypes.subtracting(["registry", "project_control"])
        let rule: (Set<String>, Set<String>) = switch predicate {
        case .answers: (["claim"], ["question"])
        case .subquestionOf: (["question"], ["question"])
        case .premiseOf: (["claim"], ["inference"])
        case .concludes: (["inference"], ["claim"])
        case .assumes: (["claim", "inference", map], ["claim"])
        case .dependsOn: (all, all)
        case .usesConcept: (["claim", "inference", "question", "position", "case"], ["concept"])
        case .hasCommitment: (["position"], ["claim"])
        case .targets: (["claim", "inference", map], ["position", "claim", "inference"])
        case .supports: (["claim", "inference"], ["claim", "inference"])
        case .objectsTo: (["claim", "inference"], ["claim", "inference", "position"])
        case .rebuts: (["claim", "inference"], ["claim"])
        case .undercuts: (["claim", "inference"], ["inference"])
        case .pressures: (["claim", "inference", "case"], ["claim", "inference", "position"])
        case .repliesTo: (["claim", "inference"], ["claim", "inference"])
        case .concedes: (["claim", "inference", "position"], ["claim"])
        case .qualifies: (["claim", "inference", relation], ["claim", "inference", relation])
        case .contradicts: (["claim"], ["claim"])
        case .elicits: (["case"], ["claim"])
        case .tests: (["case"], ["claim", "inference", "position"])
        case .illustrates: (["case", "evidence_anchor"], ["claim", "concept", "position"])
        case .counterexampleTo: (["case"], ["claim", "inference"])
        case .evidenceFor: (["evidence_anchor"], ["claim"])
        case .attributesTo: (["claim"], ["position"])
        case .interprets: (["claim"], ["evidence_anchor", "position"])
        case .isBackgroundFor: (["evidence_anchor", "claim", "position"], substantive)
        case .isNotEvidenceFor: (["evidence_anchor", "claim", "position", relation], substantive)
        case .derivedFrom, .supersedes: (all, all)
        case .extends, .refines, .questions, .incompatibleWith, .cites, .seeAlso, .connected, .isCaseFor, .isSourceFor:
            (all, all) // legacy predicates are rejected separately as noncanonical v4 syntax
        }
        return rule.0.contains(subject) && rule.1.contains(object)
    }

    public static func isUUIDv4(_ value: String) -> Bool {
        guard UUID(uuidString: value) != nil else { return false }
        let scalars = Array(value.lowercased())
        return scalars.count == 36 && scalars[14] == "4" && ["8", "9", "a", "b"].contains(scalars[19])
    }

    public static func expectedNoteTypes(for relativePath: String) -> Set<String>? {
        let path = relativePath.replacingOccurrences(of: "\\", with: "/")
        if path.hasPrefix("00 Project Control/Templates/v4/") { return noteTypes }
        if path.hasPrefix("00 Project Control/") { return ["project_control"] }
        if path.hasPrefix("01 Questions/") { return ["question"] }
        if path.hasPrefix("02 Claims/") { return ["claim"] }
        if path.hasPrefix("03 Inferences/") { return ["inference"] }
        if path.hasPrefix("04 Positions and Relations/Positions/") { return ["position"] }
        if path.hasPrefix("04 Positions and Relations/Complex Relation Records/") { return ["relation_record"] }
        if path.hasPrefix("05 Concepts/") { return ["concept"] }
        if path.hasPrefix("06 Cases/") { return ["case"] }
        if path.hasPrefix("07 Evidence and Sources/Evidence Anchors/") { return ["evidence_anchor"] }
        if path.hasPrefix("07 Evidence and Sources/Import Packets/") { return ["relation_record"] }
        if path.hasPrefix("07 Evidence and Sources/Source Control/") { return ["evidence_anchor", "relation_record"] }
        if path.hasPrefix("08 Maps and Assemblies/") { return ["assembly_map"] }
        if path.hasPrefix("09 Chapter and Draft Control/Chapter Dossiers/") { return ["chapter_dossier"] }
        if path.hasPrefix("09 Chapter and Draft Control/Draft Interfaces/") { return ["draft_interface"] }
        if path.hasPrefix("10 Registries and Review/") { return ["registry"] }
        return nil
    }

    public static func isWithinActiveTree(_ relativePath: String) -> Bool {
        let root = relativePath.split(separator: "/").first.map(String.init) ?? ""
        return root.range(of: #"^(0[0-9]|10) "#, options: .regularExpression) != nil
    }

    public static func projectRoleIsCompatible(_ role: String, noteType: String) -> Bool {
        if role == "template" { return true }
        return switch noteType {
        case "question", "claim", "inference", "position", "concept", "case", "evidence_anchor": role == "atomic_content"
        case "relation_record": role == "relation_control"
        case "assembly_map": role == "assembly"
        case "chapter_dossier": role == "chapter_control"
        case "draft_interface": role == "draft_control"
        case "registry": role == "registry" || role == "entrypoint"
        case "project_control": ["entrypoint", "control_spec", "contract", "workflow_protocol", "project_control", "archive"].contains(role)
        default: false
        }
    }
}
