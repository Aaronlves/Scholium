import Foundation

public enum ZoteroMCPAccess: String, Codable, Hashable, Sendable {
    case readOnly = "read-only"
    case full = "full"
}
