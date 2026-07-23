import Foundation
@testable import ScholiumApp

@MainActor
func makeTestWorkspaceStore() -> WorkspaceStore {
    if let explicitHome = ProcessInfo.processInfo.environment["SCHOLIUM_HOME"],
       !explicitHome.isEmpty {
        return try! WorkspaceStore(
            applicationSupportURL: URL(
                fileURLWithPath: explicitHome,
                isDirectory: true
            ).appendingPathComponent("ApplicationSupport", isDirectory: true)
        )
    }
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let supportURL = repositoryRoot
        .appendingPathComponent(".build/app-unit-state", isDirectory: true)
        .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        .appendingPathComponent("ApplicationSupport", isDirectory: true)
    return try! WorkspaceStore(applicationSupportURL: supportURL)
}
