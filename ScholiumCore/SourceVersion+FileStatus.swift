import Darwin
import ScholiumContracts

/// One filesystem-version policy for exact source reads and operation-local
/// portable inventories. The fingerprint binds admitted bytes; unchanged-file
/// checks compare the same device, inode, extent and kernel timestamps.
extension SourceVersion {
    init(fileStatus status: stat, fingerprint: DocumentFingerprint) {
        self.init(
            fingerprint: fingerprint,
            device: UInt64(status.st_dev),
            inode: UInt64(status.st_ino),
            byteCount: Int(status.st_size),
            modificationNanoseconds: Self.nanoseconds(status.st_mtimespec),
            statusChangeNanoseconds: Self.nanoseconds(status.st_ctimespec))
    }

    func matches(fileStatus status: stat) -> Bool {
        UInt64(status.st_dev) == device
            && UInt64(status.st_ino) == inode
            && Int(status.st_size) == byteCount
            && Self.nanoseconds(status.st_mtimespec) == modificationNanoseconds
            && Self.nanoseconds(status.st_ctimespec) == statusChangeNanoseconds
    }

    private static func nanoseconds(_ time: timespec) -> Int64 {
        Int64(time.tv_sec) * 1_000_000_000 + Int64(time.tv_nsec)
    }
}
