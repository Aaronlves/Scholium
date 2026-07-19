import ScholiumContracts
import SwiftUI

/// Immutable editor projection for the role-valid Research Strip. The Strip
/// owns no workflow state and performs no routing beyond emitting a semantic
/// function identifier.
struct ResearchStripPresentation {
    let items: [ResearchStripItem]
    let activeFunction: ResearchFunctionID?
}

struct ResearchStripItem: Identifiable {
    let id: ResearchFunctionID
    let isEnabled: Bool
    let disabledReason: String?

    init(
        id: ResearchFunctionID,
        isEnabled: Bool,
        disabledReason: String? = nil
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }
}

private struct ResearchStripControlFocus: Hashable {
    let function: ResearchFunctionID
    let isCompact: Bool
}

struct ResearchStripView: View {
    @FocusState private var focusedControl: ResearchStripControlFocus?
    @State private var originatingControl: ResearchStripControlFocus?

    let presentation: ResearchStripPresentation
    let select: (ResearchFunctionID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScholiumStructuralRule()
            ViewThatFits(in: .horizontal) {
                ResearchStripButtonRow(
                    presentation: presentation,
                    isCompact: false,
                    focusedControl: $focusedControl,
                    originatingControl: $originatingControl,
                    select: select
                )
                ResearchStripButtonRow(
                    presentation: presentation,
                    isCompact: true,
                    focusedControl: $focusedControl,
                    originatingControl: $originatingControl,
                    select: select
                )
            }
            .frame(maxWidth: ScholiumMetrics.Document.researchStripMaximumWidth)
            .frame(maxWidth: .infinity)
            .frame(height: ScholiumMetrics.Workspace.bottomCommandBarHeight)
        }
        .scholiumSurface(.document)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ScholiumL10n.ResearchFunction.groupAccessibilityLabel)
        .accessibilityIdentifier("scholium.researchStrip")
        .task(id: presentation.activeFunction) {
            if presentation.activeFunction != nil {
                focusedControl = nil
                return
            }
            guard let originatingControl else { return }
            self.originatingControl = nil
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedControl = originatingControl
        }
    }
}

private struct ResearchStripButtonRow: View {
    let presentation: ResearchStripPresentation
    let isCompact: Bool
    let focusedControl: FocusState<ResearchStripControlFocus?>.Binding
    @Binding var originatingControl: ResearchStripControlFocus?
    let select: (ResearchFunctionID) -> Void

    var body: some View {
        HStack(spacing: isCompact ? 0 : 2) {
            ForEach(presentation.items) { item in
                ResearchStripButton(
                    item: item,
                    isActive: presentation.activeFunction == item.id,
                    isCompact: isCompact,
                    focusedControl: focusedControl,
                    originatingControl: $originatingControl,
                    select: select
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ResearchStripButton: View {
    @State private var isHovering = false
    let item: ResearchStripItem
    let isActive: Bool
    let isCompact: Bool
    let focusedControl: FocusState<ResearchStripControlFocus?>.Binding
    @Binding var originatingControl: ResearchStripControlFocus?
    let select: (ResearchFunctionID) -> Void

    private var focusIdentity: ResearchStripControlFocus {
        ResearchStripControlFocus(function: item.id, isCompact: isCompact)
    }

    private func activate() {
        originatingControl = focusIdentity
        focusedControl.wrappedValue = focusIdentity
        select(item.id)
    }

    var body: some View {
        Button(action: activate) {
            if isCompact {
                Text(item.id.interfaceTitleResource)
                    .font(.caption.weight(isActive ? .medium : .regular))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
                    .contentShape(Rectangle())
            } else {
                Label(item.id.interfaceTitleResource, systemImage: item.id.interfaceSymbol)
                    .font(.callout.weight(isActive ? .medium : .regular))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.borderless)
        .focusable(interactions: .activate)
        .focused(focusedControl, equals: focusIdentity)
        .contentShape(Rectangle())
        .foregroundStyle(
            isActive || isHovering
                ? ScholiumColorRole.primaryText.color
                : ScholiumColorRole.secondaryText.color
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    isActive
                        ? ScholiumColorRole.accent.color
                        : ScholiumColorRole.secondaryText.color.opacity(isHovering ? 0.45 : 0)
                )
                .frame(height: 1)
                .padding(.horizontal, 10)
        }
        .onHover { isHovering = $0 }
        .disabled(!item.isEnabled)
        .help(item.disabledReason ?? item.id.interfaceHelp)
        .accessibilityLabel(item.id.interfaceTitleResource)
        .accessibilityHint(item.disabledReason ?? item.id.interfaceHelp)
        .accessibilityValue(
            isActive
                ? ScholiumL10n.ResearchFunction.openAccessibilityValue
                : ScholiumL10n.ResearchFunction.closedAccessibilityValue
        )
        .accessibilityIdentifier("scholium.researchFunction.\(item.id.interfaceIdentifier)")
    }
}

extension ResearchFunctionID {
    var interfaceSymbol: String {
        switch self {
        case .dialogue: "text.bubble"
        case .develop: "lightbulb"
        case .review: "checkmark.seal"
        case .fidelity: "checkmark.shield"
        case .critique: "doc.text.magnifyingglass"
        case .revise: "pencil"
        case .manuscript: "doc.text"
        }
    }

    var interfaceIdentifier: String {
        switch self {
        case .dialogue: "dialogue"
        case .develop: "develop"
        case .review: "review"
        case .fidelity: "fidelity"
        case .critique: "critique"
        case .revise: "revise"
        case .manuscript: "manuscript"
        }
    }
}
