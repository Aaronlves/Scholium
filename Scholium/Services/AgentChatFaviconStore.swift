import AppKit
import Foundation
import ScholiumApplication
import SwiftUI

/// One session-local favicon cache serves Chat prose and Sources. The reader
/// receives decoded PNG data only; it never requests a linked website itself.
@MainActor
final class AgentChatFaviconStore: ObservableObject {
    static let shared = AgentChatFaviconStore()

    @Published private(set) var revision = 0
    private let fetcher = AgentChatWebsiteIcons()
    private var icons: [String: LoadedIcon] = [:]

    func image(for url: URL) -> NSImage? {
        guard let host = Self.fetchableHost(for: url) else { return nil }
        return icons[host]?.image
    }

    func presentationCSS(for sources: [AgentChatReplySource]) -> String {
        let hosts = Set(sources.filter { $0.symbol == .globe }.compactMap { Self.fetchableHost(for: $0.url) })
        return hosts.sorted().compactMap { host -> String? in
            guard let icon = icons[host] else { return nil }
            return """
                .scholium-document a.scholium-chat-link[data-scholium-chat-website-host="\(host)"]::before {
                    background: url("\(icon.dataURI)") center / contain no-repeat;
                    -webkit-mask: none;
                    mask: none;
                }
                """
        }.joined(separator: "\n")
    }

    func load(_ sources: [AgentChatReplySource]) async {
        let hosts = Array(
            Set(
                sources.filter { $0.symbol == .globe }.compactMap { source -> String? in
                    guard AgentChatWebsiteIcon.image(for: source.url) == nil else { return nil }
                    return Self.fetchableHost(for: source.url)
                })
        ).sorted().prefix(12)
        let fetcher = fetcher
        await withTaskGroup(of: (String, Data?).self) { group in
            for host in hosts where icons[host] == nil {
                group.addTask { (host, await fetcher.data(for: host)) }
            }
            for await (host, data) in group {
                guard icons[host] == nil, let data, let icon = Self.decode(data) else { continue }
                icons[host] = icon
                revision += 1
            }
        }
    }

    static func fetchableHost(for url: URL) -> String? {
        AgentChatWebsiteIcons.fetchableHost(for: url)
    }

    private struct LoadedIcon {
        let image: NSImage
        let dataURI: String
    }

    private static func decode(_ data: Data) -> LoadedIcon? {
        guard let image = NSImage(data: data),
            image.size.width > 0, image.size.height > 0,
            image.size.width <= 1024, image.size.height <= 1024,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.setShouldAntialias(true)
        image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return LoadedIcon(image: image, dataURI: "data:image/png;base64,\(png.base64EncodedString())")
    }
}
