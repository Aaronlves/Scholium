import ScholiumCore
import SwiftUI

struct CritiqueRequestView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    let note: Note

    @State private var scope: CritiqueRequestScope = .overall
    @State private var lens = ""
    @State private var selectedRanges = ""
    @State private var additionalInstructions = ""
    @State private var existingCritiquePath: String?
    @State private var isCopying = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Request Critique")
                        .font(.title2.weight(.semibold))
                    Text(note.title ?? note.displayName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Critique Scope", selection: $scope) {
                        ForEach(CritiqueRequestScope.allCases, id: \.self) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    Form {
                        TextField("Disciplinary lens (optional)", text: $lens)
                        TextField("Passage, lines, section, or focus (optional)", text: $selectedRanges, axis: .vertical)
                            .lineLimit(1...3)
                        TextField("Additional instructions (optional)", text: $additionalInstructions, axis: .vertical)
                            .lineLimit(2...5)
                    }
                    .formStyle(.grouped)

                    LabeledContent("Template") {
                        HStack {
                            Text("Triptych Critique template")
                                .foregroundStyle(.secondary)
                            Button("Edit Critique Template…") {
                                UserDefaults.standard.set("research-guidance", forKey: "scholium.settings.selectedPane")
                                UserDefaults.standard.set("prompt-templates", forKey: "scholium.settings.researchGuidanceCollection")
                                UserDefaults.standard.set(ResearchPromptKind.critique.rawValue, forKey: "scholium.settings.researchGuidanceKind")
                                if let triptychID = appState.workspaceAssignment?.id {
                                    UserDefaults.standard.set(triptychID.uuidString, forKey: "scholium.settings.triptychID")
                                }
                                openSettings()
                            }
                        }
                    }

                    Label(
                        "A Critique remains separate from the Work and is read-only in Scholium. Copying creates Before Agent Work.",
                        systemImage: "doc.text.magnifyingglass"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(18)
            }

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
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isCopying)
            }
            .padding(16)
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 640, idealHeight: 760)
        .task {
            existingCritiquePath = await appState.critiqueAssociation(for: note.relativePath)?.critiqueRelativePath
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
                _ = try await appState.copyCritiqueInstructions(
                    for: note.relativePath,
                    scope: scope,
                    lens: lens,
                    selectedRanges: selectedRanges,
                    additionalInstructions: additionalInstructions
                )
                appState.showToast("Critique instructions copied. Before Agent Work checkpoint created.")
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
