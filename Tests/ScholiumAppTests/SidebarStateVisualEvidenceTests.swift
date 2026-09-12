import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

/// Opt-in native component renders, without ordered windows or research data.
@Suite("Sidebar state renders", .serialized)
@MainActor
struct SidebarStateVisualEvidenceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_SIDEBAR_STATES"] == "1"))
    func renderStates() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = repository.appendingPathComponent(".build/sidebar-states-review")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in ["en", "zh-Hans"] {
            let locale = Locale(identifier: language)
            func copy(_ value: String.LocalizationValue) -> Text { Text(ScholiumL10n.string(value, locale: locale)) }
            for scheme in [ColorScheme.light, .dark] {
                let content = VStack(alignment: .leading, spacing: 0) {
                    ScholiumSidebarState(copy("No Notes"), detail: copy("Create a Note to begin."), indicator: .symbol("doc.text"))
                    ScholiumSidebarState(copy("No Matching Notes"), detail: copy("No notes match the current filters."), indicator: .symbol("magnifyingglass"))
                    ScholiumSidebarState(copy("Loading Library…"), indicator: .progress)
                    ScholiumSidebarState(
                        copy("Could Not Open Library"), detail: Text(language == "en" ? "The selected folder is unavailable." : "所选文件夹目前无法访问。"),
                        indicator: .symbol("exclamationmark.triangle", role: .attention)
                    ) {
                        Button {
                        } label: {
                            copy("Retry")
                        }
                    }
                    ScholiumSidebarState(
                        copy("No Conversations"), detail: copy("Start a conversation about your research."), indicator: .symbol("bubble.left.and.bubble.right"))
                    ScholiumSidebarState(copy("No Archived Chats"), detail: copy("Archived conversations appear here."), indicator: .symbol("archivebox"))
                }
                .frame(width: 300)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, scheme)
                .environment(\.locale, locale)
                let host = NSHostingView(rootView: content)
                host.appearance = NSAppearance(named: scheme == .dark ? .accessibilityHighContrastDarkAqua : .aqua)
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                host.layoutSubtreeIfNeeded()
                // Flush the offscreen SwiftUI display transaction before capture.
                try await Task.sleep(for: .milliseconds(50))
                host.displayIfNeeded()
                #expect(host.bounds.width == 300)
                #expect(host.bounds.height > 0 && host.bounds.height.isFinite)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: output.appendingPathComponent("states-\(language)-\(scheme == .light ? "light" : "dark").png"))
            }
        }
    }
}
