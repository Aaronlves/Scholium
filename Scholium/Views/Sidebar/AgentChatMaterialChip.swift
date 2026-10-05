import AppKit
import ScholiumContracts
import SwiftUI

/// Compact source attachment. The conversation and runtime continue to
/// receive the untouched captured bytes.
struct AgentChatMaterialChip: View {
    let attachment: AgentChatAttachment
    var isEmbeddedInComposer = false
    let remove: (() -> Void)?
    let open: () -> Void
    @Environment(\.openChatNoteInNewTab) private var openInNewTab
    @Environment(\.openChatNoteInSeparateWindow) private var openInSeparateWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var noteIsFocused: Bool
    @FocusState private var removeIsFocused: Bool

    private var revealsRemove: Bool {
        remove != nil && (isHovered || noteIsFocused || removeIsFocused)
    }

    private var noteURL: URL { AgentChatReference.url(noteID: attachment.noteID) }

    private var title: String {
        URL(fileURLWithPath: attachment.relativePath).deletingPathExtension().lastPathComponent
    }
    private var excerpt: String { ResearchExcerptPresentation.readableText(attachment.text) }
    private var extent: String {
        String(
            localized: attachment.extent == .wholeNote ? "Whole Note" : "Attached Passage",
            bundle: .module
        )
    }
    private var source: String {
        String(
            localized: attachment.source == .editorSnapshot ? "Editor Snapshot" : "Saved Source",
            bundle: .module
        )
    }

    var body: some View {
        AgentChatMaterialContainer(isEmbeddedInComposer: isEmbeddedInComposer) {
            ZStack(alignment: .topTrailing) {
                Button(action: open) {
                    HStack(alignment: .top, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Image(systemName: attachment.extent == .wholeNote ? ScholiumSidebarItem.note.symbol : ScholiumSidebarItem.passage.symbol)
                            .font(.subheadline)
                        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                            Text(title)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: ScholiumMetrics.AgentChat.materialTitleMaximumWidth, alignment: .leading)
                                .mask {
                                    if revealsRemove {
                                        LinearGradient(
                                            stops: [
                                                .init(color: .black, location: 0),
                                                .init(color: .black, location: 0.6),
                                                .init(color: .clear, location: 1),
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    } else {
                                        Color.black
                                    }
                                }
                            if attachment.extent != .wholeNote {
                                Text(excerpt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: ScholiumMetrics.AgentChat.materialTitleMaximumWidth, alignment: .leading)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ScholiumContentActionButtonStyle(restingRole: .primaryText))
                .help(attachment.relativePath)
                .accessibilityLabel(Text("Open Note: \(title)"))
                .accessibilityValue(Text("\(extent), \(source): \(excerpt.prefix(120))"))
                .accessibilityActions {
                    if let remove {
                        Button("Remove Material", action: remove)
                    }
                }
                .focused($noteIsFocused)
                .overlay {
                    AgentChatNoteSecondaryClick(
                        open: open,
                        openNewTab: openInNewTab.map { action in { action(noteURL) } },
                        openSeparate: openInSeparateWindow.map { action in { action(noteURL) } },
                        hoverChanged: { isHovered = $0 }
                    )
                }
                if let remove {
                    Button(action: remove) {
                        ScholiumSidebarIcon(systemImage: ScholiumSidebarAction.remove.symbol, placement: .action)
                            .foregroundStyle(ScholiumColorRole.primaryText.color)
                    }
                    .buttonStyle(ScholiumContentActionButtonStyle())
                    .help("Remove Material").accessibilityLabel(Text("Remove material: \(title)"))
                    .focused($removeIsFocused)
                    .opacity(revealsRemove ? 1 : 0)
                    .allowsHitTesting(revealsRemove)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .animation(ScholiumMotion.disclosure(reduceMotion: reduceMotion), value: revealsRemove)
        }
        .accessibilityIdentifier("scholium.chat.material.\(attachment.id)")
    }
}

private struct AgentChatNoteSecondaryClick: NSViewRepresentable {
    let open: () -> Void
    let openNewTab: (() -> Void)?
    let openSeparate: (() -> Void)?
    let hoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> AgentChatNoteSecondaryClickView {
        AgentChatNoteSecondaryClickView(
            open: open, openNewTab: openNewTab, openSeparate: openSeparate,
            hoverChanged: hoverChanged)
    }

    func updateNSView(_ view: AgentChatNoteSecondaryClickView, context: Context) {
        view.open = open
        view.openNewTab = openNewTab
        view.openSeparate = openSeparate
        view.hoverChanged = hoverChanged
    }
}

private final class AgentChatNoteSecondaryClickView: NSView {
    var open: () -> Void
    var openNewTab: (() -> Void)?
    var openSeparate: (() -> Void)?
    var hoverChanged: (Bool) -> Void
    private var hoverTrackingArea: NSTrackingArea?

    init(
        open: @escaping () -> Void,
        openNewTab: (() -> Void)?,
        openSeparate: (() -> Void)?,
        hoverChanged: @escaping (Bool) -> Void
    ) {
        self.open = open
        self.openNewTab = openNewTab
        self.openSeparate = openSeparate
        self.hoverChanged = hoverChanged
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("Code-only view") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        hoverTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        if let hoverTrackingArea { addTrackingArea(hoverTrackingArea) }
    }

    override func mouseEntered(with event: NSEvent) { hoverChanged(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged(false) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard NSApp.currentEvent?.type == .rightMouseDown else { return nil }
        return super.hitTest(point)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(AgentChatNoteMenuItem(ScholiumL10n.string("Open Note"), invoke: open))
        if let openNewTab {
            menu.addItem(AgentChatNoteMenuItem(ScholiumL10n.string("Open in New Tab"), invoke: openNewTab))
        }
        if let openSeparate {
            menu.addItem(AgentChatNoteMenuItem(ScholiumL10n.string("Open in Separate Window"), invoke: openSeparate))
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// Draft materials share the composer's enclosing surface. Sent materials keep
/// their native grouping; previews retain their own native presentation.
struct AgentChatMaterialContainer<Content: View>: View {
    let isEmbeddedInComposer: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isEmbeddedInComposer {
            content()
                .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
                .accessibilityElement(children: .contain)
        } else {
            GroupBox(content: content)
        }
    }
}
