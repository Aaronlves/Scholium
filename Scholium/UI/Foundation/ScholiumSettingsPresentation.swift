import AppKit
import SwiftUI

@MainActor
func settingsMatrixHeader(
    _ title: LocalizedStringResource
) -> some View {
    Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
}

@MainActor
func settingsMatrixRowLabel(
    _ title: LocalizedStringResource
) -> some View {
    Text(title)
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
}

@MainActor
func settingsEditorSection<Content: View>(
    _ title: LocalizedStringResource,
    @ViewBuilder content: () -> Content
) -> some View {
    LabeledContent {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            content()
        }
    } label: {
        Text(title)
            .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .contain)
}

private struct ScholiumSettingsPaneSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

extension View {
    /// One system content background spans a Settings form and adjacent controls.
    /// Grouped rows retain their native surfaces; the scroll container does not
    /// introduce an independent backdrop across retained hosting boundaries.
    func scholiumSettingsFormStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    func scholiumSettingsPaneSurface() -> some View {
        modifier(ScholiumSettingsPaneSurface())
    }
}

extension EnvironmentValues {
    @Entry var scholiumSettingsSearchTarget: SettingsSection? = nil
    @Entry var scholiumSettingsSearchRevision = 0
}

extension View {
    /// Routes a static search destination into the page's existing native scroll
    /// container. It creates neither a second scroll plane nor navigation state.
    func scholiumSettingsSearchDestination() -> some View {
        modifier(SettingsSearchDestination())
    }
}

private struct SettingsSearchDestination: ViewModifier {
    @Environment(\.scholiumSettingsSearchTarget) private var target
    @Environment(\.scholiumSettingsSearchRevision) private var revision
    @Environment(\.scholiumSettingsPaneIsActive) private var isActive

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onAppear { reveal(in: proxy) }
                .onChange(of: target) { _, _ in reveal(in: proxy) }
                .onChange(of: revision) { _, _ in reveal(in: proxy) }
                .onChange(of: isActive) { _, _ in reveal(in: proxy) }
        }
    }

    private func reveal(in proxy: ScrollViewProxy) {
        guard isActive, let target else { return }
        proxy.scrollTo(target, anchor: .top)
    }
}
