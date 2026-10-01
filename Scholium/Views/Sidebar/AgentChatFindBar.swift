import SwiftUI

struct AgentChatFindBar: View {
    @Binding var query: String
    let focusRequest: UUID?
    let position: Int?
    let count: Int
    let move: (Bool) -> Void
    let dismiss: () -> Void
    var isActive = true
    @Environment(\.isEnabled) private var environmentIsEnabled
    @ScaledMetric(relativeTo: .body) private var minimumInputWidth: CGFloat =
        ScholiumGrid.Dimension.preferredCustomTarget * 3.5

    private var positionDescription: Text {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Find in Conversation")
        } else if let position {
            Text("Message \(position) of \(count)")
        } else {
            Text("No Matches")
        }
    }

    private var compactPosition: String {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "—" }
        if let position { return "\(position)/\(count)" }
        return "0"
    }

    var body: some View {
        AgentChatFindBarLayout(minimumInputWidth: minimumInputWidth) {
            ContextSearchField(
                text: $query, prompt: "Find in Conversation",
                identifier: "scholium.chat.find.query", isActive: isActive && environmentIsEnabled,
                focusRequest: focusRequest,
                navigate: move, dismiss: dismiss)
            Text(verbatim: compactPosition)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityLabel(positionDescription)
                .help(positionDescription)
            Button {
                move(true)
            } label: {
                Image(systemName: ScholiumSidebarAction.previousMatch.symbol)
            }
            .help("Previous Matching Message").accessibilityLabel("Previous Matching Message")
            .disabled(count == 0)
            Button {
                move(false)
            } label: {
                Image(systemName: ScholiumSidebarAction.nextMatch.symbol)
            }
            .help("Next Matching Message").accessibilityLabel("Next Matching Message")
            .disabled(count == 0)
            Button("Done", action: dismiss)
                .accessibilityLabel("Done")
        }
        .buttonStyle(ScholiumContentActionButtonStyle()).controlSize(.regular)
        .padding(.horizontal, ScholiumSidebarLayout.textInset)
        .padding(.vertical, ScholiumSidebarLayout.itemSpacing)
    }
}

/// Repositions one native field and its existing controls. Changing width never
/// mounts a second editor or changes the field's focus and selection identity.
private struct AgentChatFindBarLayout: Layout {
    let minimumInputWidth: CGFloat
    private let controlGap = ScholiumSidebarLayout.textSpacing
    private let rowGap = ScholiumSidebarLayout.itemSpacing

    private struct ControlRow {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func controlRows(sizes: [CGSize], width: CGFloat) -> [ControlRow] {
        var rows: [ControlRow] = []
        var row = ControlRow()
        for index in sizes.indices.dropFirst() {
            let nextWidth = row.indices.isEmpty ? sizes[index].width : row.width + controlGap + sizes[index].width
            if !row.indices.isEmpty && nextWidth > width {
                rows.append(row)
                row = ControlRow()
            }
            row.width += (row.indices.isEmpty ? 0 : controlGap) + sizes[index].width
            row.height = max(row.height, sizes[index].height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let controls = controlRows(sizes: sizes, width: .greatestFiniteMagnitude)
        let controlWidth = controls.first?.width ?? 0
        let naturalWidth = minimumInputWidth + rowGap + controlWidth
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? naturalWidth
        if width >= minimumInputWidth + rowGap + controlWidth {
            let field = subviews[0].sizeThatFits(.init(width: width - controlWidth - rowGap, height: nil))
            return CGSize(width: width, height: max(field.height, controls.first?.height ?? 0))
        }
        let field = subviews[0].sizeThatFits(.init(width: width, height: nil))
        let rows = controlRows(sizes: sizes, width: width)
        return CGSize(width: width, height: field.height + rows.reduce(0) { $0 + $1.height + rowGap })
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let controlWidth = controlRows(sizes: sizes, width: .greatestFiniteMagnitude).first?.width ?? 0
        if bounds.width >= minimumInputWidth + rowGap + controlWidth {
            let fieldWidth = bounds.width - controlWidth - rowGap
            let field = subviews[0].sizeThatFits(.init(width: fieldWidth, height: nil))
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.midY - field.height / 2),
                anchor: .topLeading, proposal: .init(width: fieldWidth, height: field.height))
            var x = bounds.minX + fieldWidth + rowGap
            for index in sizes.indices.dropFirst() {
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.midY - sizes[index].height / 2),
                    anchor: .topLeading, proposal: .init(sizes[index]))
                x += sizes[index].width + controlGap
            }
        } else {
            let field = subviews[0].sizeThatFits(.init(width: bounds.width, height: nil))
            subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: bounds.width, height: field.height))
            var y = bounds.minY + field.height + rowGap
            for row in controlRows(sizes: sizes, width: bounds.width) {
                var x = bounds.maxX - row.width
                for index in row.indices {
                    let isPosition = index == 1
                    subviews[index].place(
                        at: CGPoint(x: isPosition ? bounds.minX : x, y: y + (row.height - sizes[index].height) / 2),
                        anchor: .topLeading, proposal: .init(sizes[index]))
                    x += sizes[index].width + controlGap
                }
                y += row.height + rowGap
            }
        }
    }
}
