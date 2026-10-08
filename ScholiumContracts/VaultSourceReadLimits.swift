import Foundation

/// Source admission limits shared by descriptor reads and transient parsing.
/// A refused source remains authoritative on disk; no truncated projection is valid.
public enum VaultSourceReadLimits {
    public static let maximumNoteByteCount = 8 * 1_024 * 1_024
    package static let maximumObsidianConfigurationByteCount = 256 * 1_024
    package static let maximumInFlightSourceByteCount = 16 * 1_024 * 1_024
}
