import ScholiumContracts
import SwiftUI

private enum MethodsPracticesSection: String, CaseIterable, Hashable {
    case methods
    case practices
}

struct MethodsPracticesSettingsView: View {
    @State private var section = MethodsPracticesSection.methods

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(
                alignment: .leading,
                spacing: ScholiumGrid.Spacing.nestedContentInset
            ) {
                settingsTitle(
                    "Methods & Practices",
                    detail: "Manage each Action’s primary Method and the exact Markdown Practices those Methods link."
                )

                ScholiumSegmentedControl(
                    selection: $section,
                    options: [
                        ScholiumSegmentedControlOption(
                            .methods,
                            title: String(localized: "Methods")
                        ),
                        ScholiumSegmentedControlOption(
                            .practices,
                            title: String(localized: "Practices")
                        ),
                    ],
                    label: String(localized: "Methods and Practices section"),
                    accessibilityIdentifier: "scholium.researchGuidance.methodsPractices.section"
                )
                .frame(maxWidth: 320)
            }
            .padding(ScholiumMetrics.Settings.editorContentInset)

            Divider()

            switch section {
            case .methods:
                ResearchMethodsSettingsView(showsTitle: false)
            case .practices:
                ResearchPracticesSettingsView()
            }
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.researchGuidance.methodsPractices")
    }
}

private struct ResearchPracticeEditorContext: Identifiable {
    let practice: ResearchPracticeSnapshot

    var id: String { practice.relativePath }
}

private struct NewResearchPracticeContext: Identifiable {
    let id = UUID()
}

private struct ResearchPracticesSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var loadedTriptychID: UUID?
    @State private var practices: [ResearchPracticeSnapshot] = []
    @State private var practiceEditor: ResearchPracticeEditorContext?
    @State private var newPractice: NewResearchPracticeContext?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: ScholiumGrid.Spacing.sectionSeparation
            ) {
                researchSettingsSection("PHILOSOPHICAL PRACTICES") {
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumMetrics.ResearchGuidance.summarySpacing
                    ) {
                        HStack {
                            Text("Methods opt into Practices only through exact Wikilinks.")
                                .font(ScholiumTypography.interface(.body))
                                .scholiumForeground(.secondaryText)
                            Spacer()
                            Button("New Practice…") {
                                newPractice = NewResearchPracticeContext()
                            }
                        }

                        if isWorking && loadedTriptychID == nil {
                            ScholiumContentStateView(
                                "Loading Practices…",
                                indicator: .progress,
                                placement: .leading,
                                density: .compact
                            )
                        } else if practices.isEmpty {
                            ScholiumContentStateView(
                                "No Practices",
                                detail: Text("Create an exact Markdown Practice, then link it from a Method."),
                                indicator: .symbol("doc.text"),
                                placement: .leading,
                                density: .compact
                            )
                            .frame(maxWidth: .infinity, minHeight: 150)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(practices) { practice in
                                    practiceRow(practice)
                                    if practice.id != practices.last?.id { Divider() }
                                }
                            }
                        }
                    }
                }

                researchSettingsSection("BOUNDARY") {
                    Text("Methods and Practices guide scholarly work; they never grant Agent access or alter Session, revision, conflict, or recovery rules.")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 720, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scholiumSettingsPaneSurface()
        .disabled(
            loadedTriptychID != settingsModel.activeTriptychServicesID
                || isWorking
        )
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
        .sheet(item: $practiceEditor) { context in
            ResearchGuidanceMarkdownEditSheet(
                title: Text("Edit \(context.practice.title)"),
                detail: Text("This is exact Markdown. Saving replaces only this Practice."),
                sourceAccessibilityLabel: Text("Philosophical Practice Markdown"),
                initialSource: context.practice.source,
                save: { source in
                    _ = try await settingsModel.savePhilosophicalPractice(
                        relativePath: context.practice.relativePath,
                        source: source,
                        expectedRevision: context.practice.revision
                    )
                    await reload()
                }
            )
        }
        .sheet(item: $newPractice) { _ in
            ResearchGuidanceMarkdownCreationSheet(
                title: Text("New Philosophical Practice"),
                detail: Text("Scholium creates one ordinary Markdown document. Link its title exactly from a primary Method to include it in Research Context."),
                nameLabel: "Practice title",
                sourceAccessibilityLabel: Text("Philosophical Practice Markdown"),
                initialName: "",
                initialSource: "# Practice\n\nState the philosophical practice here.\n"
            ) { title, source in
                _ = try await settingsModel.createPhilosophicalPractice(
                    title: title,
                    source: source
                )
                await reload()
            }
        }
        .alert("Could Not Update Practices", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func practiceRow(_ practice: ResearchPracticeSnapshot) -> some View {
        researchSettingsCollectionRow {
            VStack(
                alignment: .leading,
                spacing: ScholiumGrid.Spacing.labelAccessoryGap
            ) {
                Text(practice.title)
                    .font(ScholiumTypography.interface(.rowTitle))
                Text(practice.relativePath)
                    .font(ScholiumTypography.exact(.small))
                    .scholiumForeground(.secondaryText)
                    .textSelection(.enabled)
            }
        } actions: {
            Button("Edit…") {
                practiceEditor = ResearchPracticeEditorContext(practice: practice)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchGuidance.practice.\(practice.id)")
    }

    @MainActor
    private func reload() async {
        guard let triptychID = settingsModel.activeTriptychServicesID else {
            loadedTriptychID = nil
            practices = []
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let loaded = try await settingsModel.philosophicalPractices()
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            practices = loaded.sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath)
                    == .orderedAscending
            }
            loadedTriptychID = triptychID
            errorMessage = nil
        } catch {
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            practices = []
            loadedTriptychID = triptychID
            errorMessage = error.localizedDescription
        }
    }
}
