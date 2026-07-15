import ScholiumContracts
import SwiftUI

struct CritiqueRequestContext {
    let triptychID: UUID?
    let existingCritiquePath: () async -> String?
    let copyInstructions: (CritiqueRequestScope, String, String) async throws -> Void
    let didCopyInstructions: () -> Void
}

struct CritiqueRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    let note: WindowDocumentLocation
    let context: CritiqueRequestContext

    @State private var scope: CritiqueRequestScope = .overall
    @State private var lens = ""
    @State private var selectedRanges = ""
    @State private var existingCritiquePath: String?
    @State private var isCopying = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Request Critique")
                        .font(.title2.weight(.semibold))
                    Text("Attributed agent assessment of \(note.title ?? note.displayName)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(18)
            Divider()

            Form {
                Section("Request") {
                    Picker("Critique Scope", selection: $scope) {
                        ForEach(CritiqueRequestScope.allCases, id: \.self) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Target Work") {
                        Text(note.title ?? note.displayName)
                            .lineLimit(1)
                            .help(note.relativePath)
                    }

                    if let existingCritiquePath {
                        LabeledContent("Current Critique") {
                            Text(existingCritiquePath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(existingCritiquePath)
                        }
                    }
                }

                Section("Scholarly Focus") {
                    TextField("Disciplinary lens (optional)", text: $lens)
                    TextField(
                        "Passage, lines, section, or focus (optional)",
                        text: $selectedRanges,
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                }

                Section("Research Guidance") {
                    Text("Critiques use the template configured for this Triptych.")
                        .foregroundStyle(.secondary)

                    Button("Edit Critique Template…") {
                        openCritiqueTemplateSettings()
                    }
                }

                Section {
                    Label(
                        "An external agent authors the Critique. It remains separate from the Work and read-only in Scholium. Copying creates Before Agent Work.",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    copyInstructions()
                } label: {
                    Label("Copy Instructions for Agent", systemImage: "doc.on.doc")
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isCopying)
                .accessibilityIdentifier("scholium.critique.copyInstructions")
            }
            .padding(16)
        }
        // Scholia owns the sheet-size contract. The destination must be able
        // to compress inside that height so its persistent footer never falls
        // below the sheet's interactive region on shorter displays.
        .frame(minWidth: 0, idealWidth: 760, minHeight: 0, idealHeight: 680)
        .task {
            existingCritiquePath = await context.existingCritiquePath()
        }
        .alert("Could Not Prepare Critique", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Keep Editing", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func copyInstructions() {
        Task { @MainActor in
            isCopying = true
            defer { isCopying = false }
            do {
                try await context.copyInstructions(scope, lens, selectedRanges)
                context.didCopyInstructions()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openCritiqueTemplateSettings() {
        UserDefaults.standard.set("research-guidance", forKey: "scholium.settings.selectedPane")
        UserDefaults.standard.set(
            "prompt-templates",
            forKey: "scholium.settings.researchGuidanceCollection"
        )
        UserDefaults.standard.set(
            ResearchPromptKind.critique.rawValue,
            forKey: "scholium.settings.researchGuidanceKind"
        )
        if let triptychID = context.triptychID {
            UserDefaults.standard.set(triptychID.uuidString, forKey: "scholium.settings.triptychID")
        }
        openSettings()
    }
}
