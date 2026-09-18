import Foundation

public struct ZoteroHTTPResponse: Sendable, Equatable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    func header(named name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol ZoteroHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> ZoteroHTTPResponse
}

public struct ZoteroURLSessionClient: ZoteroHTTPClient, Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: ZoteroNoRedirectDelegate(), delegateQueue: nil)
    }

    init(session: URLSession) { self.session = session }

    public func send(_ request: URLRequest) async throws -> ZoteroHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else {
            throw ZoteroLocalAPIError.invalidResponse
        }
        let maximum = 4 * 1_024 * 1_024
        guard response.expectedContentLength <= maximum else {
            throw ZoteroLocalAPIError.responseTooLarge
        }
        let body = try await withTaskCancellationHandler {
            var body = Data()
            for try await byte in bytes {
                guard body.count < maximum else { throw ZoteroLocalAPIError.responseTooLarge }
                if body.count.isMultiple(of: 8_192) { try Task.checkCancellation() }
                body.append(byte)
            }
            try Task.checkCancellation()
            return body
        } onCancel: {
            bytes.task.cancel()
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            result[String(describing: entry.key)] = String(describing: entry.value)
        }
        return ZoteroHTTPResponse(
            statusCode: response.statusCode, headers: headers, body: body
        )
    }
}

enum ZoteroLocalAPIError: LocalizedError, Sendable {
    case invalidResponse
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Zotero returned an invalid local API response."
        case .responseTooLarge: "The Zotero local API response exceeded Scholium's bounded read limit."
        }
    }
}
