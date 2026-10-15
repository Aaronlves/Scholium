import Darwin

/// Byte identity for App-owned source projections. Unicode canonical equality
/// cannot identify the exact Markdown or labels retained by those projections.
enum ScholiumExactUTF8 {
    struct SourceIdentity: Equatable, Sendable {
        let source: String

        init(_ source: String) { self.source = source }

        static func == (lhs: Self, rhs: Self) -> Bool { ScholiumExactUTF8.equal(lhs.source, rhs.source) }
    }

    nonisolated static func equal(_ lhs: String, _ rhs: String) -> Bool {
        // Native Strings share their existing storage. A foreign String may
        // need temporary contiguous storage; neither pointer escapes its scope.
        var lhs = lhs
        var rhs = rhs
        return lhs.withUTF8 { left in
            rhs.withUTF8 { right in
                guard left.count == right.count else { return false }
                if left.isEmpty || left.baseAddress == right.baseAddress { return true }
                return memcmp(left.baseAddress!, right.baseAddress!, left.count) == 0
            }
        }
    }

    nonisolated static func hasPrefix(_ source: String, _ prefix: String) -> Bool {
        var source = source
        var prefix = prefix
        return source.withUTF8 { bytes in
            prefix.withUTF8 { leading in
                guard bytes.count >= leading.count else { return false }
                if leading.isEmpty || bytes.baseAddress == leading.baseAddress { return true }
                return memcmp(bytes.baseAddress!, leading.baseAddress!, leading.count) == 0
            }
        }
    }
}
