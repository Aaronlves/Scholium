import AppKit
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Runtime approval presentation", .serialized)
@MainActor
struct AgentChatRuntimeApprovalPresentationTests {
    private let english = Locale(identifier: "en")

    @Test("Command scope keeps the exact directory, environment, denied network and bounded file rules")
    func commandScope() throws {
        let command = "printf '%s\\n' '原文 **source**'\n"
        let request = try CodexChatRuntimeApproval.parse(
            method: "item/commandExecution/requestApproval",
            params: [
                "command": .string(command), "cwd": .string("/fixture/Analyses 原文"),
                "environmentId": .string("research-environment"),
                "additionalPermissions": .object([
                    "network": .object(["enabled": .bool(false)]),
                    "fileSystem": .object([
                        "read": .array([.string("/fixture/Analyses 原文")]),
                        "entries": .array([
                            .object([
                                "access": .string("write"),
                                "path": .object(["type": .string("glob_pattern"), "pattern": .string("/fixture/Works/**/*.md")]),
                            ]),
                            .object([
                                "access": .string("deny"),
                                "path": .object([
                                    "type": .string("special"),
                                    "value": .object(["kind": .string("project_roots"), "subpath": .string("private")]),
                                ]),
                            ]),
                        ]),
                        "globScanMaxDepth": .integer(2),
                    ]),
                ]),
            ], item: nil
        ).presentation

        #expect(
            request.scopeLines(locale: english) == [
                "Working Directory: /fixture/Analyses 原文",
                "Execution Environment: research-environment",
                "Network Access: Disabled",
                "Read Files: /fixture/Analyses 原文",
                "Write Files: Pattern: /fixture/Works/**/*.md",
                "Deny File Access: Project Roots / private",
                "Pattern Scan Depth: 2",
            ])
        #expect(request.command?.utf8.elementsEqual(command.utf8) == true)
        #expect(request.publicDescription.contains(command))
        #expect(request.grants == [.once] && request.rejection == .decline)
    }

    @Test("Managed network approval shows the exact protocol and destination without relabelling opaque command metadata")
    func networkScope() throws {
        let request = try CodexChatRuntimeApproval.parse(
            method: "item/commandExecution/requestApproval",
            params: [
                "command": .string("opaque-network-operation"),
                "cwd": .string("/fixture"), "environmentId": .string("environment-2"),
                "networkApprovalContext": .object([
                    "host": .string("papers.example.test:8443"), "protocol": .string("socks5Udp"),
                ]),
            ], item: nil
        ).presentation
        #expect(request.kind == .network)
        #expect(
            request.scopeLines(locale: english) == [
                "Network Destination: socks5Udp · papers.example.test:8443",
                "Working Directory: /fixture",
                "Execution Environment: environment-2",
            ])
        #expect(!request.publicDescription.contains("opaque-network-operation"))
    }

    @Test("Missing permission observations do not become disabled or unrestricted access")
    func absentScope() throws {
        let request = try CodexChatRuntimeApproval.parse(
            method: "item/permissions/requestApproval",
            params: ["cwd": .string("/fixture"), "permissions": .object([:])], item: nil
        ).presentation
        #expect(request.scopeLines(locale: english) == ["Working Directory: /fixture"])
        #expect(request.permissions?.network == nil && request.permissions?.globScanMaxDepth == nil)
        #expect(request.grants == [.turn, .session])

        let withoutProtocol = AgentChatRuntimeApproval(
            kind: .network, command: nil, cwd: nil, environmentID: nil, reason: nil,
            networkHost: "papers.example.test", networkProtocol: nil, permissions: nil,
            files: [], grantRoot: nil, grants: [.once], rejection: .decline)
        #expect(withoutProtocol.scopeLines(locale: english) == ["Network Destination: papers.example.test"])
    }

    @Test("File proposals distinguish same-name files and show full move destinations and exact diff bytes")
    func fileTargetsAndDiffs() throws {
        let diff = "\u{FEFF}@@ -1 +1 @@\r\n-旧的论点 **source** 😀\r\n+修订后的论点 **source** 😀\r\n"
        let request = try fileRequest(diff: diff)
        #expect(
            request.files.map { $0.label(locale: english) } == [
                "Edit File: /fixture/Analyses/Argument.md → /fixture/Works/Argument.md",
                "Delete File: /fixture/Topics/Argument.md",
            ])
        #expect(request.files[0].displayedDiff(locale: english).utf8.elementsEqual(diff.utf8))
        #expect(request.files[1].displayedDiff(locale: english) == "No diff text was supplied.")
        #expect(request.files[1].displayedDiff(locale: Locale(identifier: "zh-Hans")) == "未提供差异文本。")
        #expect(request.files[1].diff.isEmpty)
        #expect(request.scopeLines(locale: english) == ["Requested Session Write Folder: /fixture"])
        #expect(request.grants == [.session] && request.rejection == .decline)
    }

    @Test("Long file proposals keep a bounded request viewport and retain the complete diff")
    func longDiffViewport() throws {
        _ = NSApplication.shared
        let diff = (0..<400).map { "+exact passage \($0) 原文 😀\r\n" }.joined()
        let request = try fileRequest(diff: diff)
        for width: CGFloat in [260, 340] {
            let host = NSHostingView(
                rootView: AgentChatRuntimeApprovalView(
                    request: request, decision: nil, failure: nil, stop: {}, respond: { _ in }
                )
                .environment(\.locale, english)
                .environment(\.agentChatContentMaximumHeight, 160)
                .frame(width: width))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: 500),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer {
                window.contentView = nil
                window.close()
            }
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize.height > 160 && host.fittingSize.height < 260)
            #expect(request.files[0].displayedDiff(locale: english).utf8.elementsEqual(diff.utf8))
            #expect(request.files[0].diff.utf8.elementsEqual(diff.utf8))
        }
    }

    private func fileRequest(diff: String) throws -> AgentChatRuntimeApproval {
        try CodexChatRuntimeApproval.parse(
            method: "item/fileChange/requestApproval",
            params: ["grantRoot": .string("/fixture")],
            item: .init(
                .object([
                    "type": .string("fileChange"),
                    "changes": .array([
                        .object([
                            "path": .string("/fixture/Analyses/Argument.md"), "diff": .string(diff),
                            "kind": .object(["type": .string("update"), "move_path": .string("/fixture/Works/Argument.md")]),
                        ]),
                        .object([
                            "path": .string("/fixture/Topics/Argument.md"), "diff": .string(""),
                            "kind": .object(["type": .string("delete")]),
                        ]),
                    ]),
                ]))
        ).presentation
    }
}
