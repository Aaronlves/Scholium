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

struct ResearchStripSurfaceStyle: Equatable {
    let usesOpaqueBackground: Bool
    let separatorOpacity: Double

    init(reduceTransparency: Bool) {
        usesOpaqueBackground = reduceTransparency
        separatorOpacity = reduceTransparency ? 0.72 : 0.28
    }
}

private struct ResearchStripControlFocus: Hashable {
    let function: ResearchFunctionID
    let isCompact: Bool
}

struct ResearchStripView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var focusedControl: ResearchStripControlFocus?
    @State private var originatingControl: ResearchStripControlFocus?

    let presentation: ResearchStripPresentation
    let select: (ResearchFunctionID) -> Void

    private var surfaceStyle: ResearchStripSurfaceStyle {
        ResearchStripSurfaceStyle(reduceTransparency: reduceTransparency)
    }

    var body: some View {
        GlassEffectContainer(spacing: 4) {
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
        }
        .background(
            surfaceStyle.usesOpaqueBackground
                ? Color(nsColor: .controlBackgroundColor)
                : Color.clear,
            in: Capsule()
        )
        .glassEffect(.regular, in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    Color(nsColor: .separatorColor).opacity(surfaceStyle.separatorOpacity),
                    lineWidth: 0.75
                )
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Research functions")
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
            }
        }
        .padding(4)
    }
}

private struct ResearchStripButton: View {
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
                Text(item.id.interfaceTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
            } else {
                Label(item.id.interfaceTitle, systemImage: item.id.interfaceSymbol)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.borderless)
        .focusable(interactions: .activate)
        .focused(focusedControl, equals: focusIdentity)
        .background(
            isActive ? Color.accentColor.opacity(0.16) : Color.clear,
            in: Capsule()
        )
        .disabled(!item.isEnabled)
        .help(item.disabledReason ?? item.id.interfaceHelp)
        .accessibilityLabel(item.id.interfaceTitle)
        .accessibilityHint(item.disabledReason ?? item.id.interfaceHelp)
        .accessibilityValue(isActive ? "Open" : "Closed")
        .accessibilityIdentifier("scholium.researchFunction.\(item.id.interfaceIdentifier)")
    }
}

extension ResearchFunctionID {
    var interfaceTitle: String {
        switch self {
        case .dialogue: "Dialogue"
        case .develop: "Develop"
        case .review: "Review"
        case .fidelity: "Fidelity"
        case .critique: "Critique"
        case .revise: "Revise"
        case .manuscript: "Manuscript"
        }
    }

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

    var interfaceHelp: String {
        switch self {
        case .dialogue: "Open a scholarly Dialogue for this note"
        case .develop: "Develop this Analysis or Topic"
        case .review: "Review and qualify this Analysis or Topic"
        case .fidelity: "Check philosophical content and citations"
        case .critique: "Request an attributed Critique of this Work"
        case .revise: "Prepare a substantive revision of this Work"
        case .manuscript: "Coordinate work on this manuscript"
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
