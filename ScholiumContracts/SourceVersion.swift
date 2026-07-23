import Foundation

/// Exact content fingerprint plus the descriptor-observed filesystem version
/// used by a rebuildable source catalog to avoid rereading unchanged files.
public struct SourceVersion: Codable, Hashable, Sendable {
    public let fingerprint: DocumentFingerprint
    public let device: UInt64
    public let inode: UInt64
    public let byteCount: Int
    public let modificationNanoseconds: Int64
    public let statusChangeNanoseconds: Int64

    public init(
        fingerprint: DocumentFingerprint,
        device: UInt64,
        inode: UInt64,
        byteCount: Int,
        modificationNanoseconds: Int64,
        statusChangeNanoseconds: Int64
    ) {
        self.fingerprint = fingerprint
        self.device = device
        self.inode = inode
        self.byteCount = byteCount
        self.modificationNanoseconds = modificationNanoseconds
        self.statusChangeNanoseconds = statusChangeNanoseconds
    }
}
