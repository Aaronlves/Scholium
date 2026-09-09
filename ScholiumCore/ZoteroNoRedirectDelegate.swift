import Foundation

/// Local API transports never follow a server redirect to a different resource or authority.
public final class ZoteroNoRedirectDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable {
    public override init() { super.init() }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
