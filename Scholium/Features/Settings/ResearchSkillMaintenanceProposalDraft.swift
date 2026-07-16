import Foundation
import ScholiumContracts

enum ResearchSkillMaintenanceProposalDraftError: LocalizedError {
    case invalidJSON(String)
    case staleCurrentPackage

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            "The returned proposal is not a complete Researcher Skill package: \(detail)"
        case .staleCurrentPackage:
            "The complete Researcher Skill package changed. Reload it before requesting a proposal."
        }
    }
}

struct ResearchSkillMaintenanceFileComparison: Hashable, Identifiable {
    let relativePath: String
    let kind: ResearchSkillMaintenanceChangeKind
    let currentSource: String?
    let proposedSource: String?

    var id: String { relativePath }
}

/// Pure frontend drafting support for the explicit external proposal handoff.
/// It handles only delivery-neutral Contracts values and never sees package
/// locations, bindings, stores, or filesystem state.
enum ResearchSkillMaintenanceProposalDraft {
    static func decode(_ source: String) throws -> ResearchSkillProposedPackage {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw ResearchSkillMaintenanceProposalDraftError.invalidJSON(
                "Paste the complete returned JSON package first."
            )
        }
        do {
            let package = try JSONDecoder().decode(
                ResearchSkillProposedPackage.self,
                from: data
            )
            try package.validate()
            return package
        } catch let error as ResearchSkillMaintenanceError {
            throw ResearchSkillMaintenanceProposalDraftError.invalidJSON(
                error.localizedDescription
            )
        } catch {
            throw ResearchSkillMaintenanceProposalDraftError.invalidJSON(
                error.localizedDescription
            )
        }
    }

    static func encode(_ package: ResearchSkillProposedPackage) throws -> String {
        try package.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(package), as: UTF8.self)
    }

    static func proposalRequest(
        packageID: String,
        currentPackage: ResearchSkillProposedPackage,
        expectedPackageRevision: DocumentFingerprint,
        purpose: String
    ) throws -> String {
        let normalizedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPurpose.isEmpty else {
            throw ResearchSkillMaintenanceError.emptyInstruction
        }
        try currentPackage.validate()
        guard currentPackage.packageRevision == expectedPackageRevision else {
            throw ResearchSkillMaintenanceProposalDraftError.staleCurrentPackage
        }
        let packageJSON = try encode(currentPackage)
        return """
        Propose a bounded update to this complete Triptych-local Researcher Skill package for the stated maintenance purpose. Preserve source fidelity, researcher authority, and the package's actual philosophical workflow. Do not change anything merely for stylistic novelty.

        Package ID:
        \(packageID)

        Current whole-package revision:
        \(expectedPackageRevision.sha256) (\(expectedPackageRevision.byteCount) bytes)

        Maintenance purpose:
        \(normalizedPurpose)

        Complete current package (JSON):
        \(packageJSON)

        Return only one complete ResearchSkillProposedPackage JSON object with a `files` array. Every retained file must be present; omission means deletion. Each file must contain `relativePath` and exact UTF-8 `source`; the derived `revision` may be omitted. Allowed paths are `SKILL.md` and one-level files under `references/`, `templates/`, or `evals/`. Do not return a patch, prose explanation, package ID, filesystem path, confirmation token, or evaluation report.
        """
    }

    static func comparisons(
        current: ResearchSkillProposedPackage,
        proposed: ResearchSkillProposedPackage
    ) -> [ResearchSkillMaintenanceFileComparison] {
        let currentFiles = Dictionary(
            current.files.map { ($0.relativePath, $0.source) },
            uniquingKeysWith: { first, _ in first }
        )
        let proposedFiles = Dictionary(
            proposed.files.map { ($0.relativePath, $0.source) },
            uniquingKeysWith: { first, _ in first }
        )
        return Set(currentFiles.keys).union(proposedFiles.keys).sorted().map { path in
            let currentSource = currentFiles[path]
            let proposedSource = proposedFiles[path]
            let kind: ResearchSkillMaintenanceChangeKind
            switch (currentSource, proposedSource) {
            case (nil, .some):
                kind = .added
            case (.some, nil):
                kind = .removed
            case let (.some(before), .some(after)) where before != after:
                kind = .modified
            default:
                kind = .unchanged
            }
            return ResearchSkillMaintenanceFileComparison(
                relativePath: path,
                kind: kind,
                currentSource: currentSource,
                proposedSource: proposedSource
            )
        }
    }
}
