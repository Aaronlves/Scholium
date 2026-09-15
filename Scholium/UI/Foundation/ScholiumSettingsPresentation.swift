import AppKit
import SwiftUI

/// The shared presentation boundary for Scholium's macOS Settings window.
/// Native controls retain their platform behavior; this layer supplies only
/// label alignment and spacing shared by every Settings pane. System
/// typography, colors, materials and control feedback remain native.
@MainActor
func settingsTitle(
    _ title: LocalizedStringResource,
    detail: LocalizedStringResource
) -> some View {
    VStack(
        alignment: .leading,
        spacing: ScholiumMetrics.SettingsPresentation.titleDetailSpacing
    ) {
        Text(title)
            .font(.title2)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
        Text(detail)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    .frame(
        maxWidth: ScholiumMetrics.Settings.headerMaximumWidth,
        alignment: .leading
    )
    .accessibilityElement(children: .contain)
}

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

/// A semantic settings group; macOS owns its surface, corners, and adaptation.
@MainActor
func settingsGroup<Content: View>(
    _ title: LocalizedStringResource,
    @ViewBuilder content: () -> Content
) -> some View {
    GroupBox {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ScholiumGrid.Spacing.inlineControlGap)
    } label: {
        Text(title).accessibilityAddTraits(.isHeader)
    }
}

@MainActor
func settingsFormSection<Content: View>(
    _ title: LocalizedStringResource,
    @ViewBuilder content: () -> Content
) -> some View {
    settingsEditorSection(title, content: content)
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

struct ScholiumSettingsSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = ScholiumL10n.string("Search Settings")
        searchField.sendsSearchStringImmediately = true
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.searchChanged(_:))
        searchField.setAccessibilityLabel(ScholiumL10n.string("Search Settings"))
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ScholiumSettingsSearchField

        init(parent: ScholiumSettingsSearchField) {
            self.parent = parent
        }

        @objc func searchChanged(_ sender: NSSearchField) {
            parent.text = sender.stringValue
        }
    }
}

extension View {
    func scholiumSettingsPaneSurface() -> some View {
        modifier(ScholiumSettingsPaneSurface())
    }
}
