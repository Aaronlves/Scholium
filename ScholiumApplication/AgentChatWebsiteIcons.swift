import Foundation
import ScholiumCore

/// Session-local domain admission, request deduplication and bounded favicon cache.
public actor AgentChatWebsiteIcons {
    public init() {}
    private var tasks: [String: Task<Data?, Never>] = [:]
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public func data(for host: String) async -> Data? {
        guard let url = URL(string: "https://\(host)"), Self.fetchableHost(for: url) == host else { return nil }
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
        return await WebsiteIconTransport.download(host: host)
    }

    /// Only HTTPS DNS names can trigger a request. Link paths and queries,
    /// credentials, IP literals, local names and sample domains are excluded.
    public nonisolated static func fetchableHost(for url: URL) -> String? {
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

    private nonisolated static func isDNSLabel(_ label: Substring) -> Bool {
        let bytes = Array(label.utf8)
        guard !bytes.isEmpty, bytes.count <= 63,
            let first = bytes.first, let last = bytes.last,
            isASCIIAlphanumeric(first), isASCIIAlphanumeric(last)
        else { return false }
        return bytes.allSatisfy { isASCIIAlphanumeric($0) || $0 == 45 }
    }

    private nonisolated static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (97...122).contains(byte) || (48...57).contains(byte)
    }

}
