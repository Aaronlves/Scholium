import ScholiumContracts
import SwiftUI

/// Immutable document projections and explicit research/navigation effects
/// needed by the Critique provenance strip.
struct CritiqueProvenanceContext {
    let availableNotes: [WindowDocumentLocation]
    let documentRevisions: [String: DocumentFingerprint]
    let loadAssociation: @MainActor (String) async throws -> CritiqueAssociation?
    let openTarget: @MainActor (String) -> Void
    let openFinding: @MainActor (CritiqueFinding, String?) -> Void
}

/// A compact, document-local authority surface for agent-authored Critiques.
/// The prose remains the primary surface; this strip only exposes provenance,
/// revision binding, and explicit finding destinations before the body.
struct CritiqueProvenanceView: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    let note: WindowDocumentLocation
    let context: CritiqueProvenanceContext

    @State private var association: CritiqueAssociation?
    @State private var findingsAreExpanded = false

    init(
        note: WindowDocumentLocation,
        context: CritiqueProvenanceContext
    ) {
        self.note = note
        self.context = context
    }

    private var document: NoteDocument {
        note.document
    }

    private var metadata: CritiqueDocumentMetadata {
        CritiqueDocumentContract.metadata(in: document)
    }

    private var findings: [CritiqueFinding] {
        CritiqueDocumentContract.findings(in: document)
    }

    private var targetPath: String? {
        association?.workRelativePath ?? metadata.targetRelativePath
    }

    private var targetNote: WindowDocumentLocation? {
        guard let targetPath else { return nil }
        return context.availableNotes.first { $0.relativePath == targetPath }
    }

    private var capturedSHA256: String? {
        association?.targetFingerprint.sha256 ?? metadata.targetFingerprintSHA256
    }

    private var metadataMismatchesAssociation: Bool {
        guard let association else { return false }
        if let metadataPath = metadata.targetRelativePath,
           metadataPath != association.workRelativePath { return true }
        if let metadataSHA = metadata.targetFingerprintSHA256,
           metadataSHA != association.targetFingerprint.sha256 { return true }
        return false
    }

    private var isStale: Bool {
        guard let capturedSHA256,
              let targetPath,
              let current = context.documentRevisions[targetPath] else { return false }
        return current.sha256 != capturedSHA256
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(
                    metadata.isAgentAttributed ? "Agent-authored Critique" : "Agent attribution missing",
                    systemImage: metadata.isAgentAttributed ? "sparkles" : "exclamationmark.triangle"
                )
                .font(ScholiumTypography.interface(.sectionTitle))
                .scholiumForeground(
                    metadata.isAgentAttributed ? .agentAuthorship : .attention
                )
                .accessibilityLabel(
                    metadata.isAgentAttributed
                        ? "Agent-authored Critique"
                        : "Agent attribution missing"
                )

                Spacer(minLength: 12)

                if let scope = metadata.scope {
                    Text(scope.rawValue)
                        .font(ScholiumTypography.interface(.small))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("Target")
                    .font(ScholiumTypography.interface(.body))
                    .foregroundStyle(.secondary)
                if let targetPath {
                    Button {
                        context.openTarget(targetPath)
                    } label: {
                        Text(targetNote?.title ?? targetNote?.displayName ?? targetPath)
                            .font(ScholiumTypography.interface(.body))
                    }
                    .buttonStyle(.link)
                    .disabled(targetNote == nil)
                    .help(targetNote == nil ? "The target Work is unavailable." : targetPath)
                } else {
                    Text("Not recorded")
                        .scholiumForeground(.attention)
                }

                if let capturedSHA256 {
                    Text("SHA-256 \(capturedSHA256.prefix(12))…")
                        .font(ScholiumTypography.exact(.small))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 8)

                if isStale {
                    Label("Earlier Work version", systemImage: "clock.badge.exclamationmark")
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .scholiumForeground(.attention)
                } else if targetNote != nil, capturedSHA256 != nil {
                    Label("Current Work version", systemImage: "checkmark.circle")
                        .font(ScholiumTypography.interface(.small))
                        .foregroundStyle(.secondary)
                }
            }

            if metadataMismatchesAssociation {
                Label(
                    "Critique metadata does not match the latest recorded request. Treat its target as uncertain until the agent or researcher reconciles it.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.attention)
            } else if association == nil {
                Label(
                    "No Scholium request history is associated with this Critique.",
                    systemImage: "info.circle"
                )
                .font(ScholiumTypography.interface(.small))
                .foregroundStyle(.secondary)
            }

            if !findings.isEmpty {
                Button {
                    findingsAreExpanded.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.right")
                            .font(ScholiumTypography.interface(.small, emphasis: .strong))
                            .scholiumForeground(.mutedText)
                            .frame(width: 12)
                            .rotationEffect(.degrees(findingsAreExpanded ? 90 : 0))
                            .animation(
                                ScholiumMotion.disclosure(reduceMotion: reduceMotion),
                                value: findingsAreExpanded
                            )
                            .accessibilityHidden(true)
                        Text("Specific Findings")
                            .font(ScholiumTypography.interface(.sectionTitle))
                        Spacer(minLength: 8)
                        Text(findings.count.formatted())
                            .font(ScholiumTypography.interface(.small, tabularDigits: true))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Specific Findings")
                .accessibilityValue(
                    "\(findingsAreExpanded ? "Expanded" : "Collapsed"), \(findings.count) \(findings.count == 1 ? "finding" : "findings")"
                )
                .accessibilityHint(
                    findingsAreExpanded
                        ? "Hides the source-anchored Critique findings."
                        : "Shows the source-anchored Critique findings."
                )
                .accessibilityIdentifier("scholium.critiqueFindings")

                if findingsAreExpanded {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(findings) { finding in
                            findingButton(finding)
                        }
                    }
                    .padding(.top, 7)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .task(id: note.relativePath + document.fingerprint.sha256) {
            association = try? await context.loadAssociation(note.relativePath)
        }
        .onChange(of: note.relativePath) { _, _ in
            findingsAreExpanded = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.critiqueProvenance")
    }

    @ViewBuilder
    private func findingButton(_ finding: CritiqueFinding) -> some View {
        let path = finding.targetRelativePath ?? targetPath
        let target = path.flatMap { candidate in
            context.availableNotes.first { $0.relativePath == candidate }
        }
        let resolvedLine = target.flatMap {
            finding.resolvedTargetLine(in: $0.document)
        }
        let stale = finding.targetFingerprintSHA256.map { sha in
            path.flatMap { context.documentRevisions[$0]?.sha256 } != sha
        } ?? isStale

        Button {
            context.openFinding(finding, targetPath)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: stale ? "clock.badge.exclamationmark" : "arrow.right.circle")
                    .scholiumForeground(stale ? .attention : .secondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(finding.judgment.rawValue): \(finding.title)")
                        .foregroundStyle(.primary)
                    Text(findingDestination(
                        finding,
                        path: path,
                        stale: stale,
                        anchorResolved: resolvedLine != nil
                    ))
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(stale ? .attention : .secondaryText)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil || resolvedLine == nil)
        .accessibilityLabel("\(finding.judgment.rawValue): \(finding.title)")
        .accessibilityValue(findingDestination(
            finding,
            path: path,
            stale: stale,
            anchorResolved: resolvedLine != nil
        ))
        .accessibilityHint(
            target == nil
                ? "The target Work is unavailable."
                : resolvedLine == nil
                    ? "The recorded heading or quotation does not identify one exact passage."
                    : "Opens the recorded Work passage."
        )
        .accessibilityIdentifier("scholium.critiqueFinding.\(finding.critiqueSourceLine)")
    }

    private func findingDestination(
        _ finding: CritiqueFinding,
        path: String?,
        stale: Bool,
        anchorResolved: Bool
    ) -> String {
        var parts: [String] = []
        if let path { parts.append(path) }
        if let heading = finding.targetHeading { parts.append("Heading: \(heading)") }
        if let line = finding.targetLine { parts.append("Line \(line)") }
        if finding.targetLine == nil, finding.targetHeading == nil,
           finding.targetQuotation != nil { parts.append("Quoted passage") }
        parts.append("Critique line \(finding.critiqueSourceLine)")
        if stale { parts.append("earlier target version") }
        if !anchorResolved { parts.append("anchor unresolved") }
        return parts.joined(separator: " — ")
    }
}
