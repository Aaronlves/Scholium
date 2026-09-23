import Foundation

/// Fetches bounded icon bytes for a domain admitted by Application.
public enum WebsiteIconTransport {
    public static func download(host: String) async -> Data? {
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
