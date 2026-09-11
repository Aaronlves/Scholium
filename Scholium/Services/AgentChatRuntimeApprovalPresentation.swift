import Foundation
import ScholiumContracts

extension AgentChatRuntimeApproval {
    func title(locale: Locale = .current) -> String {
        switch kind {
        case .command: ScholiumL10n.string("Run Command", locale: locale)
        case .network: ScholiumL10n.string("Network Access", locale: locale)
        case .terminalInput: ScholiumL10n.string("Send Terminal Input", locale: locale)
        case .files: ScholiumL10n.string("Runtime File Proposal", locale: locale)
        case .permissions: ScholiumL10n.string("Request Access", locale: locale)
        case .tool: ScholiumL10n.string("Run Tool", locale: locale)
        }
    }
    func question(locale: Locale = .current) -> String {
        switch kind {
        case .command: ScholiumL10n.string("Run this command?", locale: locale)
        case .terminalInput: ScholiumL10n.string("Send input to the running command?", locale: locale)
        case .network: ScholiumL10n.string("Allow this internet connection?", locale: locale)
        case .files: ScholiumL10n.string("Apply these file changes?", locale: locale)
        case .permissions: ScholiumL10n.string("Allow this access?", locale: locale)
        case .tool: ScholiumL10n.string(isScholiumNoteUpdate ? "Allow a note change request?" : "Allow this tool to run?", locale: locale)
        }
    }

    private var isScholiumNoteUpdate: Bool {
        kind == .tool && toolServer == "scholium"
            && reason == "Allow the scholium MCP server to run tool \"scholium_update_note\"?"
    }

    func explanation(locale: Locale = .current) -> String? {
        if isScholiumNoteUpdate {
            return ScholiumL10n.string("You will review the exact changes before they are saved.", locale: locale)
        }
        return reason
    }

    /// A readable overview retaining exact targets and restrictions.
    func accessOverview(locale: Locale = .current) -> [String] {
        var lines: [String] = []
        if let host = networkHost { lines.append(ScholiumL10n.string("Connect to \(host)", locale: locale)) }
        if let permissions {
            if permissions.network == true { lines.append(ScholiumL10n.string("Connect to the internet", locale: locale)) }
            for rule in permissions.rules {
                let target: String
                switch rule.path {
                case .literal(let path): target = path
                case .pattern(let pattern):
                    let base = String(pattern.dropLast(min(pattern.count, "/**/*.md".count)))
                    if pattern.hasSuffix("/**/*.md"), !base.isEmpty,
                        !base.contains(where: { "*?[]{}\\".contains($0) }), permissions.globScanMaxDepth == nil
                    {
                        let folder = base
                        target = ScholiumL10n.string("Markdown files in \(folder) and its subfolders", locale: locale)
                    } else {
                        target = pattern
                    }
                case .special(let root, let subpath): target = root.label(locale: locale) + (subpath.map { " / " + $0 } ?? "")
                }
                switch rule.access {
                case .read: lines.append(ScholiumL10n.string("Read: \(target)", locale: locale))
                case .write: lines.append(ScholiumL10n.string("Change: \(target)", locale: locale))
                case .deny: lines.append(ScholiumL10n.string("Keep inaccessible: \(target)", locale: locale))
                }
            }
        }
        for file in files {
            let name = URL(fileURLWithPath: file.path).lastPathComponent
            let action =
                switch file.kind {
                case .add: ScholiumL10n.string("Create File", locale: locale)
                case .delete: ScholiumL10n.string("Delete File", locale: locale)
                case .update: ScholiumL10n.string("Edit File", locale: locale)
                }
            lines.append(action + ": " + name + (file.destination.map { " → " + URL(fileURLWithPath: $0).lastPathComponent } ?? ""))
        }
        if let grantRoot { lines.append(ScholiumL10n.string("Change files in: \(grantRoot)", locale: locale)) }
        return lines
    }

    func scopeLines(locale: Locale = .current) -> [String] {
        var lines: [String] = []
        if let toolServer { lines.append(toolServer) }
        if let networkHost { lines.append(ScholiumL10n.string("Network Destination", locale: locale) + ": " + (networkProtocol ?? "") + " · " + networkHost) }
        if let cwd { lines.append(ScholiumL10n.string("Working Directory", locale: locale) + ": " + cwd) }
        if let environmentID { lines.append(ScholiumL10n.string("Execution Environment", locale: locale) + ": " + environmentID) }
        if let grantRoot { lines.append(ScholiumL10n.string("Requested Session Write Folder", locale: locale) + ": " + grantRoot) }
        if let permissions {
            if let enabled = permissions.network {
                lines.append(
                    enabled ? ScholiumL10n.string("Network Access: Enabled", locale: locale) : ScholiumL10n.string("Network Access: Disabled", locale: locale))
            }
            lines += permissions.rules.map { $0.access.label(locale: locale) + ": " + $0.path.label(locale: locale) }
            if let depth = permissions.globScanMaxDepth { lines.append(ScholiumL10n.string("Pattern Scan Depth: \(depth)", locale: locale)) }
        }
        return lines
    }
    var publicDescription: String {
        ([title(), kind == .network ? nil : command, reason].compactMap { $0 } + scopeLines()
            + files.map {
                $0.label() + "\n" + $0.diff
            }).joined(separator: "\n\n")
    }
}

extension AgentChatRuntimeApproval.Decision {
    func label(locale: Locale = .current) -> String {
        switch self {
        case .once: ScholiumL10n.string("Allow Once", locale: locale)
        case .turn: ScholiumL10n.string("Allow for This Turn", locale: locale)
        case .session: ScholiumL10n.string("Allow for Session", locale: locale)
        case .decline: ScholiumL10n.string("Decline", locale: locale)
        case .cancel: ScholiumL10n.string("Stop Turn", locale: locale)
        }
    }
    var isGrant: Bool { self == .once || self == .turn || self == .session }
}

extension AgentChatRuntimeApproval.Access {
    func label(locale: Locale = .current) -> String {
        switch self {
        case .read: ScholiumL10n.string("Read Files", locale: locale)
        case .write: ScholiumL10n.string("Write Files", locale: locale)
        case .deny: ScholiumL10n.string("Deny File Access", locale: locale)
        }
    }
}

extension AgentChatRuntimeApproval.Path {
    func label(locale: Locale = .current) -> String {
        switch self {
        case .literal(let path): path
        case .pattern(let pattern): ScholiumL10n.string("Pattern", locale: locale) + ": " + pattern
        case .special(let root, let subpath): root.label(locale: locale) + (subpath.map { " / " + $0 } ?? "")
        }
    }
}

extension AgentChatRuntimeApproval.Root {
    func label(locale: Locale = .current) -> String {
        switch self {
        case .root: ScholiumL10n.string("All Files", locale: locale)
        case .minimal: ScholiumL10n.string("Runtime Minimum Files", locale: locale)
        case .projectRoots: ScholiumL10n.string("Project Roots", locale: locale)
        case .temporaryDirectory: ScholiumL10n.string("Runtime Temporary Directory", locale: locale)
        case .systemTemporaryDirectory: "/tmp"
        }
    }
}

extension AgentChatRuntimeApproval.File {
    func label(locale: Locale = .current) -> String {
        let effect =
            switch kind {
            case .add: ScholiumL10n.string("Create File", locale: locale)
            case .delete: ScholiumL10n.string("Delete File", locale: locale)
            case .update: ScholiumL10n.string("Edit File", locale: locale)
            }
        return effect + ": " + path + (destination.map { " → " + $0 } ?? "")
    }
}
