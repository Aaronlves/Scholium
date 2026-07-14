import SwiftUI

// MARK: - Metadata Card View

/// Compact single-line header at the top of a note. Default collapsed state shows
/// title, first author, year, status, and KB indicator. Expand for full metadata.
struct MetadataCardView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let note: Note

    /// `nil` means the researcher has not overridden this vault's configured
    /// starting disclosure state for the current note session.
    @State private var disclosureOverride: Bool?

    private struct MetadataGroup: Identifiable {
        let name: String
        let keys: [String]
        var id: String { name }
    }

    private struct DisplayField: Identifiable {
        let key: String
        let label: String
        let value: String
        var id: String { key }
    }

    private var groups: [(name: String, fields: [DisplayField])] {
        let definitions: [MetadataGroup]
        if let configured = appState.currentPropertiesConfiguration {
            definitions = [MetadataGroup(name: "Properties", keys: configured.visibleFields)]
        } else { switch note.profile {
        case .paperAnalysis:
            definitions = [
                MetadataGroup(name: "About", keys: ["title", "authors", "year", "type", "tags"]),
                MetadataGroup(name: "Source", keys: ["access", "text_reliability", "locators", "audit.status", "audit.last_checked_at", "audit.checks.human_reviewed"]),
                MetadataGroup(name: "Progress", keys: ["status"]),
                MetadataGroup(name: "Use", keys: ["relevance"]),
                MetadataGroup(name: "History", keys: ["created", "updated"]),
            ]
        case .topicKnowledge:
            definitions = [
                MetadataGroup(name: "About", keys: ["title", "aliases", "tags"]),
                MetadataGroup(name: "Progress", keys: ["status"]),
                MetadataGroup(name: "History", keys: ["created", "updated"]),
            ]
        case .dissertationControl:
            definitions = [
                MetadataGroup(name: "About", keys: [
                    "note_type", "project_role", "origin", "evidential_layer", "claim_type",
                    "question_kind", "claim_kind", "inference_type", "inference_force",
                    "position_kind", "concept_kind", "case_kind", "evidence_kind",
                    "verification_state", "source_locator", "predicate", "semantic_direction",
                    "assembly_kind", "chapter_id", "workflow_stage", "draft_target",
                    "registry_kind", "indexed_note_types", "control_kind",
                ]),
                MetadataGroup(name: "Progress", keys: ["status", "settlement_degree", "settlement_dimensions", "review_status", "confidence", "evidence_state"]),
                MetadataGroup(name: "Use", keys: ["prose_permission", "reopen_condition", "privacy", "provenance"]),
                MetadataGroup(name: "History", keys: ["created_at", "updated_at", "last_reviewed", "migration_state"]),
            ]
        case .draftProject:
            definitions = [
                MetadataGroup(name: "About", keys: ["title", "authors", "kind", "tags"]),
                MetadataGroup(name: "Progress", keys: ["status"]),
                MetadataGroup(name: "Use", keys: ["venue", "deadline"]),
                MetadataGroup(name: "History", keys: ["created", "updated"]),
            ]
        case .generic:
            definitions = [MetadataGroup(
                name: "Properties",
                keys: note.frontmatter.keys.filter { !ResearcherPropertyPolicy.isHidden($0) }.sorted()
            )]
        } }

        return definitions.compactMap { group in
            var fields = group.keys.compactMap { key -> DisplayField? in
                guard !ResearcherPropertyPolicy.isHidden(key),
                      let rawValue = note.property(at: key),
                      let value = displayValue(rawValue) else { return nil }
                let schemaLabel = FrontmatterSchema.schema(for: note)
                    .fields.first(where: { $0.key == key })?.label
                return DisplayField(key: key, label: schemaLabel ?? humanized(key), value: value)
            }
            if group.name == "Progress" && appState.currentVaultRole.allowsHumanReview {
                fields.insert(DisplayField(key: "application_review", label: "Scholium Review", value: applicationReviewLabel), at: 0)
            }
            return fields.isEmpty ? nil : (group.name, fields)
        }
    }

    private var isExpanded: Bool {
        disclosureOverride ?? appState.currentPropertiesConfiguration?.isExpanded ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                let nextValue = !isExpanded
                if reduceMotion {
                    disclosureOverride = nextValue
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        disclosureOverride = nextValue
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(note.title ?? note.displayName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if let authors = note.authors.first {
                        Text(authors)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let year = note.year {
                        Text(year.formatted(.number.grouping(.never)))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Text("Properties")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .accessibilityLabel(isExpanded ? "Hide note properties" : "Show note properties")
            .accessibilityValue(note.title ?? note.displayName)
            .accessibilityIdentifier("scholium.metadataDisclosure")

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    if groups.isEmpty {
                        Text("No configured Properties fields are present in this note.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groups, id: \.name) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .accessibilityAddTraits(.isHeader)

                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 190), alignment: .topLeading)],
                                    alignment: .leading,
                                    spacing: 8
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

                    HStack {
                        Button {
                            appState.editingNotePath = note.relativePath
                            appState.showFrontmatterEditor = true
                        } label: {
                            Label("Edit Properties", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!appState.canEditCurrentNote)

                        Spacer()

                        let visibleCount = groups.reduce(0) { $0 + $1.fields.count }
                        Text("\(visibleCount) shown propert\(visibleCount == 1 ? "y" : "ies")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .onChange(of: note.relativePath) { _, _ in disclosureOverride = nil }
    }

    private var applicationReviewLabel: String {
        if appState.changedSinceReviewPaths.contains(note.relativePath) { return "Changed since review" }
        if note.isReviewed { return "Reviewed exact file bytes" }
        return "Not yet reviewed in Scholium"
    }

    private func displayValue(_ value: FrontmatterValue) -> String? {
        switch value {
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed.replacingOccurrences(of: "_", with: " ")
        case .int(let value): return value.formatted(.number.grouping(.never))
        case .double(let value): return value.formatted()
        case .bool(let value): return value ? "Yes" : "No"
        case .date(let value): return value.formatted(date: .abbreviated, time: .shortened)
        case .array(let values):
            let nonempty = values.filter { !$0.isEmpty }
            return nonempty.isEmpty ? nil : nonempty.joined(separator: ", ")
        case .dictionary(let values):
            return values.isEmpty ? nil : "\(values.count) structured fields"
        }
    }

    private func humanized(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
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
    let note = Note(
        relativePath: "papers/test.md",
        frontmatter: ["title": .string("Test"), "authors": .array(["Author"]), "year": .int(2024)],
        body: "Body",
        rawContent: "---\ntitle: Test\n---\nBody"
    )
    MetadataCardView(
        note: note
    )
        .environmentObject(AppState())
        .frame(width: 600)
}
