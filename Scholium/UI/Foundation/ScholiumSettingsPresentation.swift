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
func settingsSectionTitle(
    _ title: LocalizedStringResource
) -> some View {
    Text(title)
        .font(.headline)
        .foregroundStyle(.primary)
        .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
        .accessibilityAddTraits(.isHeader)
}

@MainActor
func settingsEditorSection<Content: View>(
    _ title: LocalizedStringResource,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(alignment: .top, spacing: 16) {
        Text(verbatim: String(localized: title) + ":")
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.trailing)
            .frame(width: 160, alignment: .trailing)
            .padding(.top, 3)
            .accessibilityAddTraits(.isHeader)
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .contain)
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

private struct ScholiumSettingsFormPresentation: ViewModifier {
    func body(content: Content) -> some View {
        ScrollView {
            content
                .formStyle(.columns)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(
                    maxWidth: 760,
                    alignment: .topLeading
                )
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scholiumSettingsPaneSurface()
    }
}

extension View {
    func scholiumSettingsPaneSurface() -> some View {
        modifier(ScholiumSettingsPaneSurface())
    }

    func scholiumSettingsForm() -> some View {
        modifier(ScholiumSettingsFormPresentation())
    }
}
