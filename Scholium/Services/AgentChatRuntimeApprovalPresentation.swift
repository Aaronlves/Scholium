import ScholiumContracts
import Foundation

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
  func scopeLines(locale: Locale = .current) -> [String] {
    var lines: [String] = []
    if let toolServer { lines.append(toolServer) }
    if let networkHost { lines.append(ScholiumL10n.string("Network Destination", locale: locale) + ": " + (networkProtocol ?? "") + " · " + networkHost) }
    if let cwd { lines.append(ScholiumL10n.string("Working Directory", locale: locale) + ": " + cwd) }
    if let environmentID { lines.append(ScholiumL10n.string("Execution Environment", locale: locale) + ": " + environmentID) }
    if let grantRoot { lines.append(ScholiumL10n.string("Requested Session Write Folder", locale: locale) + ": " + grantRoot) }
    if let permissions {
      if let enabled = permissions.network {
        lines.append(enabled ? ScholiumL10n.string("Network Access: Enabled", locale: locale) : ScholiumL10n.string("Network Access: Disabled", locale: locale))
      }
      lines += permissions.rules.map { $0.access.label(locale: locale) + ": " + $0.path.label(locale: locale) }
      if let depth = permissions.globScanMaxDepth { lines.append(ScholiumL10n.string("Pattern Scan Depth: \(depth)", locale: locale)) }
    }
    return lines
  }
  var publicDescription: String {
    ([title(), kind == .network ? nil : command, reason].compactMap { $0 } + scopeLines() + files.map {
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
    let effect = switch kind {
    case .add: ScholiumL10n.string("Create File", locale: locale)
    case .delete: ScholiumL10n.string("Delete File", locale: locale)
    case .update: ScholiumL10n.string("Edit File", locale: locale)
    }
    return effect + ": " + path + (destination.map { " → " + $0 } ?? "")
  }
}
