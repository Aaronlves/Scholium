import AppKit
import Foundation
import SwiftUI

/// One session-local favicon cache serves Chat prose and Sources. The reader
/// receives decoded PNG data only; it never requests a linked website itself.
@MainActor
final class AgentChatFaviconStore: ObservableObject {
    static let shared = AgentChatFaviconStore()

    @Published private(set) var revision = 0
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
        await withTaskGroup(of: (String, Data?).self) { group in
            for host in hosts where icons[host] == nil {
                group.addTask { (host, await FaviconFetcher.shared.data(for: host)) }
            }
            for await (host, data) in group {
                guard icons[host] == nil, let data, let icon = Self.decode(data) else { continue }
                icons[host] = icon
                revision += 1
            }
        }
    }

    /// Only HTTPS DNS names can trigger a request. Link paths and queries,
    /// credentials, IP literals, local names and sample domains are excluded.
    static func fetchableHost(for url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
            let host = url.host?.lowercased(), host.count <= 253
        else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy(isDNSLabel),
            let topLevel = labels.last,
            topLevel.utf8.contains(where: { (97...122).contains($0) })
        else { return nil }
        let reserved: Set<String> = [
            "local", "localhost", "internal", "test", "invalid",
            "example", "onion", "lan", "home", "arpa",
        ]
        guard !reserved.contains(String(topLevel)),
            !["example.com", "example.net", "example.org"].contains(where: {
                host == $0 || host.hasSuffix(".\($0)")
            })
        else { return nil }
        return host
    }

    private static func isDNSLabel(_ label: Substring) -> Bool {
        let bytes = Array(label.utf8)
        guard !bytes.isEmpty, bytes.count <= 63,
            let first = bytes.first, let last = bytes.last,
            isASCIIAlphanumeric(first), isASCIIAlphanumeric(last)
        else { return false }
        return bytes.allSatisfy { isASCIIAlphanumeric($0) || $0 == 45 }
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (97...122).contains(byte) || (48...57).contains(byte)
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

private actor FaviconFetcher {
    static let shared = FaviconFetcher()
    private var tasks: [String: Task<Data?, Never>] = [:]
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func data(for host: String) async -> Data? {
        if let task = tasks[host] { return await task.value }
        guard tasks.count < 128 else { return nil }
        let task = Task { await limitedDownload(host: host) }
        tasks[host] = task
        return await task.value
    }

    private func limitedDownload(host: String) async -> Data? {
        if active < 4 {
            active += 1
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
        defer {
            if waiting.isEmpty {
                active -= 1
            } else {
                waiting.removeFirst().resume()
            }
        }
        return await Self.download(host: host)
    }

    private static func download(host: String) async -> Data? {
        guard let url = URL(string: "https://\(host)/favicon.ico") else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration, delegate: NoFaviconRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("bytes=0-131071", forHTTPHeaderField: "Range")
        request.setValue(
            "image/x-icon,image/vnd.microsoft.icon,image/png,image/jpeg,image/gif,image/webp",
            forHTTPHeaderField: "Accept"
        )
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                [200, 206].contains(response.statusCode),
                [
                    "image/x-icon", "image/vnd.microsoft.icon", "image/png",
                    "image/jpeg", "image/gif", "image/webp",
                ].contains(response.mimeType?.lowercased() ?? ""),
                response.expectedContentLength <= 131_072
            else { return nil }
            var data = Data()
            data.reserveCapacity(16_384)
            for try await byte in bytes {
                guard data.count < 131_072 else { return nil }
                data.append(byte)
            }
            return data.isEmpty ? nil : data
        } catch {
            return nil
        }
    }
}

private final class NoFaviconRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
