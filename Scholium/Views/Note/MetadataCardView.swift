import ScholiumContracts
import SwiftUI

// MARK: - Metadata Card View

/// Centers the complete document-context cluster on the prose measure. The
/// controls and Properties strip divide that measure; neither protrudes beyond
/// the document column.
struct DocumentMeasureAlignedLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let availableWidth = max(0, proposal.width ?? ScholiumMetrics.ContextSurface.clusterMeasure)
        let childWidth = min(availableWidth, ScholiumMetrics.ContextSurface.clusterMeasure)
        let childSize = subview.sizeThatFits(
            ProposedViewSize(width: childWidth, height: proposal.height)
        )
        return CGSize(width: availableWidth, height: childSize.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let childWidth = min(bounds.width, ScholiumMetrics.ContextSurface.clusterMeasure)
        let childProposal = ProposedViewSize(width: childWidth, height: nil)
        let childSize = subview.sizeThatFits(childProposal)
        let originX = bounds.midX - (childSize.width / 2)

        subview.place(
            at: CGPoint(x: originX, y: bounds.minY),
            anchor: .topLeading,
            proposal: childProposal
        )
    }
}

/// A compact, role-aware Properties summary that expands into the configured
/// human-facing metadata without competing with the document itself.
struct MetadataCardView<LeadingControls: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let note: WindowDocumentLocation
    let propertiesConfiguration: VaultPropertiesConfiguration?
    let canEdit: Bool
    let changedSinceReview: Bool
    let editProperties: () -> Void
    private let leadingControls: LeadingControls

    /// `nil` means the researcher has not overridden this vault's configured
    /// starting disclosure state for the current note session.
    @State private var disclosureOverride: Bool?

    init(
        note: WindowDocumentLocation,
        propertiesConfiguration: VaultPropertiesConfiguration? = nil,
        canEdit: Bool = false,
        changedSinceReview: Bool = false,
        editProperties: @escaping () -> Void = {},
        @ViewBuilder leadingControls: () -> LeadingControls
    ) {
        self.note = note
        self.propertiesConfiguration = propertiesConfiguration
        self.canEdit = canEdit
        self.changedSinceReview = changedSinceReview
        self.editProperties = editProperties
        self.leadingControls = leadingControls()
    }

    private var groups: [MetadataDisplayGroup] {
        let definitions: [MetadataGroup]
        if let configured = propertiesConfiguration {
            definitions = [MetadataGroup(name: "Properties", keys: configured.visibleFields)]
        } else if note.profile == .generic {
            definitions = [MetadataGroup(
                name: "Properties",
                keys: note.frontmatter.keys.filter {
                    $0 != "research_unit" && !ResearcherPropertyPolicy.isHidden($0)
                }.sorted()
            )]
        } else {
            var grouped = Dictionary(
                grouping: PropertyPresentationCatalog.presentations(for: note.schemaProfile)
                    .filter { $0.key != "research_unit" },
                by: \.group
            )
            if note.profile == .paperAnalysis {
                let audit = [
                    PropertyPresentation(
                        key: "audit.status", label: "Audit Status", help: nil,
                        group: .source, order: 100, controlStyle: .textField
                    ),
                    PropertyPresentation(
                        key: "audit.last_checked_at", label: "Audit Last Checked", help: nil,
                        group: .source, order: 101, controlStyle: .dateField
                    ),
                    PropertyPresentation(
                        key: "audit.checks.human_reviewed", label: "Human Reviewed", help: nil,
                        group: .source, order: 102, controlStyle: .toggle
                    ),
                ]
                grouped[.source, default: []].append(contentsOf: audit)
            }
            definitions = PropertyPresentationGroup.allCases.compactMap { group in
                let keys = grouped[group, default: []]
                    .sorted { $0.order < $1.order }
                    .map(\.key)
                return keys.isEmpty ? nil : MetadataGroup(name: group.label, keys: keys)
            }
        }

        return definitions.compactMap { group in
            var fields = group.keys.compactMap { key -> MetadataDisplayField? in
                guard key != "research_unit",
                      !ResearcherPropertyPolicy.isHidden(key),
                      let rawValue = note.property(at: key),
                      let value = displayValue(rawValue) else { return nil }
                let label = PropertyPresentationCatalog.presentation(
                    for: key,
                    in: note.schemaProfile
                )?.label
                return MetadataDisplayField(key: key, label: label ?? humanized(key), value: value)
            }
            if group.name == "Progress" && note.vaultRole.allowsHumanReview {
                fields.insert(
                    MetadataDisplayField(
                        key: "application_review",
                        label: "Scholium Review",
                        value: applicationReviewLabel
                    ),
                    at: 0
                )
            }
            return fields.isEmpty ? nil : MetadataDisplayGroup(name: group.name, fields: fields)
        }
    }

    private var summaryFields: [MetadataDisplayField] {
        let preferredKeys: [String]
        switch note.profile {
        case .paperAnalysis:
            preferredKeys = ["authors", "year", "debate_importance", "status", "type"]
        case .topicKnowledge:
            preferredKeys = ["status", "aliases", "tags"]
        case .dissertationControl, .draftProject:
            preferredKeys = ["kind", "note_type", "status", "authors", "deadline"]
        case .generic:
            preferredKeys = []
        }

        let allFields = groups.flatMap(\.fields).filter { $0.key != "title" }
        var seenKeys: Set<String> = []
        var ordered: [MetadataDisplayField] = []

        for key in preferredKeys {
            guard let field = allFields.first(where: { $0.key == key }),
                  seenKeys.insert(field.key).inserted else { continue }
            ordered.append(compactSummaryField(field))
        }
        for field in allFields where ordered.count < 3 {
            guard seenKeys.insert(field.key).inserted else { continue }
            ordered.append(compactSummaryField(field))
        }
        return Array(ordered.prefix(3))
    }

    private var isExpanded: Bool {
        disclosureOverride ?? propertiesConfiguration?.isExpanded ?? false
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: ScholiumMetrics.ContextSurface.columnSpacing) {
                leadingControls
                    .frame(
                        width: ScholiumMetrics.ContextSurface.leadingControlsWidth,
                        height: ScholiumMetrics.ContextSurface.controlHeight
                    )

                Button {
                    let nextValue = !isExpanded
                    if reduceMotion {
                        disclosureOverride = nextValue
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) {
                            disclosureOverride = nextValue
                        }
                    }
                } label: {
                    MetadataSummaryRow(
                        role: note.profile.displayName,
                        fields: summaryFields,
                        isExpanded: isExpanded
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: ScholiumMetrics.ContextSurface.metadataMeasure)
                .frame(height: ScholiumMetrics.ContextSurface.controlHeight)
                .background(
                    reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            Color(nsColor: .separatorColor).opacity(reduceTransparency ? 0.72 : 0.28),
                            lineWidth: 0.75
                        )
                        .allowsHitTesting(false)
                }
                .shadow(
                    color: Color(nsColor: .shadowColor).opacity(reduceTransparency ? 0.05 : 0.10),
                    radius: 10,
                    y: 4
                )
                .accessibilityLabel(isExpanded ? "Hide note properties" : "Show note properties")
                .accessibilityValue(note.title ?? note.displayName)
                .accessibilityHint("Shows the configured Properties for this note")
                .accessibilityIdentifier("scholium.metadataDisclosure")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                MetadataDetailsPanel(
                    groups: groups,
                    researchUnit: note.researchUnit,
                    canEdit: canEdit,
                    reduceTransparency: reduceTransparency
                ) { editProperties() }
                .frame(maxWidth: .infinity)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
                )
            }
        }
        .frame(maxWidth: ScholiumMetrics.ContextSurface.clusterMeasure)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.documentContextCluster")
        .onChange(of: note.relativePath) { _, _ in disclosureOverride = nil }
    }

    private var applicationReviewLabel: String {
        if changedSinceReview { return "Changed since review" }
        if note.isReviewed { return "Reviewed exact file bytes" }
        return "Not yet reviewed in Scholium"
    }

    private func displayValue(_ value: YAMLValue) -> String? {
        switch value {
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed.replacingOccurrences(of: "_", with: " ")
        case .integer(let value): return value.formatted(.number.grouping(.never))
        case .double(let value): return value.formatted()
        case .boolean(let value): return value ? "Yes" : "No"
        case .null: return nil
        case .array(let values):
            let nonempty = values.map(\.displayScalar).filter { !$0.isEmpty }
            return nonempty.isEmpty ? nil : nonempty.joined(separator: ", ")
        case .object(let values):
            return values.isEmpty ? nil : "\(values.count) structured fields"
        }
    }

    private func humanized(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func compactSummaryField(_ field: MetadataDisplayField) -> MetadataDisplayField {
        let compactLabel: String
        let compactValue: String
        switch field.key {
        case "authors":
            compactLabel = note.authors.count == 1 ? "Author" : "Authors"
            compactValue = field.value
        case "year":
            compactLabel = "Year"
            compactValue = field.value
        case "debate_importance":
            compactLabel = "Importance"
            compactValue = "\(field.value) of 10"
        default:
            compactLabel = field.label
            compactValue = field.value
        }
        return MetadataDisplayField(key: field.key, label: compactLabel, value: compactValue)
    }
}

private struct MetadataGroup: Identifiable {
    let name: String
    let keys: [String]
    var id: String { name }
}

private struct MetadataDisplayGroup: Identifiable {
    let name: String
    let fields: [MetadataDisplayField]
    var id: String { name }
}

private struct MetadataDisplayField: Identifiable {
    let key: String
    let label: String
    let value: String
    var id: String { key }
}

private struct MetadataSummaryRow: View {
    let role: String
    let fields: [MetadataDisplayField]
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(role)
                .font(ScholiumInterfaceTypography.compactEmphasis)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            ViewThatFits(in: .horizontal) {
                MetadataSummaryFacts(fields: Array(fields.prefix(3)))
                MetadataSummaryFacts(fields: Array(fields.prefix(2)))
                MetadataSummaryFacts(fields: Array(fields.prefix(1)))
                Color.clear.frame(width: 0, height: 1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                Text("Properties")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: ScholiumMetrics.ContextSurface.controlHeight)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MetadataSummaryFacts: View {
    let fields: [MetadataDisplayField]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(fields) { field in
                HStack(spacing: 5) {
                    Text(field.label)
                        .foregroundStyle(.secondary)
                    Text(field.value)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
                .font(.callout)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

private struct MetadataDetailsPanel: View {
    let groups: [MetadataDisplayGroup]
    let researchUnit: ResearchUnitDeclaration
    let canEdit: Bool
    let reduceTransparency: Bool
    let edit: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ResearchStatusPropertiesView(researchUnit: researchUnit)

            if groups.isEmpty {
                Text("No other configured Properties fields are present in this note.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groups) { group in
                    MetadataPropertyGroupView(group: group)
                }
            }

            HStack {
                Spacer()
                Button(action: edit) {
                    Label("Edit Properties…", systemImage: "slider.horizontal.3")
                }
                    .buttonStyle(.borderless)
                    .disabled(!canEdit)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if reduceTransparency {
                shape.fill(Color(nsColor: .controlBackgroundColor))
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .overlay {
            shape
                .stroke(
                    Color(nsColor: .separatorColor).opacity(reduceTransparency ? 0.78 : 0.34),
                    lineWidth: 0.75
                )
                .allowsHitTesting(false)
        }
        .shadow(
            color: Color(nsColor: .shadowColor).opacity(reduceTransparency ? 0.04 : 0.08),
            radius: 12,
            y: 4
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.metadataPanel")
    }
}

private struct MetadataPropertyGroupView: View {
    let group: MetadataDisplayGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.name)
                .font(ScholiumInterfaceTypography.overline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), alignment: .topLeading)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(group.fields) { field in
                    MetadataFact(
                        label: field.label,
                        value: field.value,
                        usesTint: field.key == "doi"
                    )
                }
            }
        }
    }
}

private struct ResearchStatusPropertiesView: View {
    let researchUnit: ResearchUnitDeclaration

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("RESEARCH STATUS")
                .font(ScholiumInterfaceTypography.overline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            switch researchUnit.state {
            case .absent:
                Label("Scope not declared", systemImage: "circle.dashed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Research Status: Scope not declared")
            case .declared:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), alignment: .topLeading)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    if let scope = researchUnit.scope {
                        MetadataFact(label: "Scope", value: scope)
                    }
                    if !researchUnit.limitations.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Limitations")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(researchUnit.limitations.map { "– \($0)" }.joined(separator: "\n"))
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            case .invalid(let message):
                Label("Could not read Research Status", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetadataFact: View {
    let label: String
    let value: String
    var usesTint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .foregroundStyle(usesTint ? Color.accentColor : Color.primary)
                .lineLimit(2)
                .help(value)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview {
    let note = WindowDocumentLocation.unclassified(NoteDocument(
        relativePath: "papers/test.md",
        rawContent: "---\ntitle: Test\nauthors: [Author]\nyear: 2024\n---\nBody"
    ))
    MetadataCardView(note: note) {
        Label("Document controls", systemImage: "book")
            .labelStyle(.iconOnly)
            .frame(
                width: ScholiumMetrics.ContextSurface.leadingControlsWidth,
                height: ScholiumMetrics.ContextSurface.controlHeight
            )
    }
        .frame(width: 1040)
}
