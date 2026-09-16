import SwiftUI

/// Shared actions in Library and Chat. Domain-specific tool/state symbols remain
/// with their existing presentation models; these values grant no action authority.
enum ScholiumSidebarAction: CaseIterable {
    case back, add, newConversation, newNote, newFolder, more, search, outline, archive, restore, delete, copy, quote, edit, branch, retry, expand, close,
        remove, earlier, later, previousMatch, nextMatch

    var symbol: String {
        switch self {
        case .back: "chevron.backward"
        case .add: "plus"
        case .newConversation: "square.and.pencil"
        case .newNote: "doc.badge.plus"
        case .newFolder: "folder.badge.plus"
        case .more: "ellipsis"
        case .search: "magnifyingglass"
        case .outline: "list.bullet.indent"
        case .archive: "archivebox"
        case .restore: "arrow.uturn.backward"
        case .delete: "trash"
        case .copy: ScholiumSystemSymbol.copyDocuments.systemName
        case .quote: ScholiumSystemSymbol.textQuote.systemName
        case .edit: "pencil"
        case .branch: "arrow.triangle.branch"
        case .retry: "arrow.clockwise"
        case .expand: ScholiumSystemSymbol.expand.systemName
        case .close: "xmark"
        case .remove: "xmark.circle"
        case .earlier: "arrow.up"
        case .later: "arrow.down"
        case .previousMatch: "chevron.up"
        case .nextMatch: "chevron.down"
        }
    }
}

/// Object identity stays distinct from an action on the object. In particular,
/// citations/sources and supplied materials must never share one symbol.
enum ScholiumSidebarItem: CaseIterable {
    case note, folder, file, image, webpage, sources, materials, passage, plan, context, skill

    var symbol: String {
        switch self {
        case .note: ScholiumSystemSymbol.docText.systemName
        case .folder: "folder"
        case .file: "doc"
        case .image: "photo"
        case .webpage: "globe"
        case .sources: "books.vertical"
        case .materials: ScholiumSystemSymbol.paperclip.systemName
        case .passage: ScholiumSystemSymbol.textQuote.systemName
        case .plan: "checklist"
        case .context: "chart.pie"
        case .skill: "square.stack"
        }
    }
}

/// A glyph is not a hit target. Row accessories use the shared icon gutter;
/// standalone actions use the full custom-control target. Native source lists
/// and header controls retain their own system-scaled geometry.
struct ScholiumSidebarIcon: View {
    enum Placement { case accessory, action }
    let systemImage: String
    var placement: Placement = .accessory

    var body: some View {
        Image(systemName: systemImage)
            .font(.callout)
            .imageScale(.small)
            .symbolRenderingMode(.monochrome)
            .frame(
                width: placement == .action ? ScholiumGrid.Dimension.preferredCustomTarget : ScholiumGrid.Dimension.iconTrackWidth,
                height: placement == .action ? ScholiumGrid.Dimension.preferredCustomTarget : ScholiumGrid.Dimension.minimumCustomTarget
            )
            .contentShape(Rectangle())
    }
}

/// Menus retain text; compact action rows opt into the same named icon label.
struct ScholiumSidebarActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.icon
            .font(.callout).imageScale(.small)
            .symbolRenderingMode(.monochrome)
            .frame(width: ScholiumGrid.Dimension.preferredCustomTarget, height: ScholiumGrid.Dimension.preferredCustomTarget)
            .contentShape(Rectangle())
    }
}

/// Success is a confirmed clipboard write, not a completed Agent turn.
struct ScholiumSidebarCopyIcon: View {
    let copied: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScholiumSidebarIcon(systemImage: copied ? "checkmark" : ScholiumSidebarAction.copy.symbol, placement: .action)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
    }
}

/// All content copies share confirmed success, native symbol replacement and
/// a restartable feedback lifetime. The caller retains clipboard-content authority.
struct ScholiumCopyButton: View {
    var label: LocalizedStringKey = "Copy"
    var contentIdentity = ""
    let copy: () -> Bool
    @State private var copied = false
    @State private var confirmation = 0

    var body: some View {
        Button {
            copied = copy()
            confirmation += 1
            if copied {
                NSAccessibility.post(
                    element: NSApp as Any, notification: .announcementRequested,
                    userInfo: [.announcement: ScholiumL10n.string("Copied"), .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
        } label: {
            ScholiumSidebarCopyIcon(copied: copied)
        }
        .help(copied ? Text("Copied") : Text(label))
        .accessibilityLabel(copied ? Text("Copied") : Text(label))
        .onChange(of: contentIdentity) { _, _ in
            copied = false
            confirmation += 1
        }
        .task(id: confirmation) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copied = false
        }
    }
}

/// Used only by custom disclosures; native Outline/DisclosureGroup arrows stay native.
struct ScholiumSidebarDisclosureIndicator: View {
    let isExpanded: Bool
    var animates = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var windowState
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption).symbolRenderingMode(.monochrome)
            .animation(ScholiumMotion.disclosure(reduceMotion: reduceMotion || !animates || windowState == .inactive)) { image in
                image.rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .frame(width: ScholiumGrid.Dimension.iconTrackWidth)
            .accessibilityHidden(true)
    }
}
