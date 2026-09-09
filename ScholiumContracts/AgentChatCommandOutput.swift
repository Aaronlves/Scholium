import Foundation

/// One bounded public command log. It is neither a visible excerpt nor private reasoning.
public enum AgentChatCommandOutput {
    public static let maximumUTF8Bytes = 256 * 1_024

    public static func appending(_ delta: String, to activity: inout AgentChatActivity) {
        retain(activity.detail + delta, in: &activity)
    }

    public static func reconciling(_ incoming: AgentChatActivity, with previous: AgentChatActivity?) -> AgentChatActivity {
        guard incoming.kind == .command else { return incoming }
        var result = incoming
        if let previous, previous.kind == .command {
            result.outputTruncated = previous.outputTruncated == true || incoming.outputTruncated == true
            let old = previous.detail, new = incoming.detail
            if new.hasPrefix(old), previous.outputTruncated != true {
                retain(new, in: &result)
            } else if old.hasSuffix(new) {
                retain(old, in: &result)
            } else {
                retain(old + String(decoding: Array(new.utf8).dropFirst(overlap(old, new)), as: UTF8.self), in: &result)
            }
        } else { retain(incoming.detail, in: &result) }
        return result
    }

    private static func retain(_ text: String, in activity: inout AgentChatActivity) {
        guard text.utf8.count > maximumUTF8Bytes else { activity.detail = text; return }
        // Discard only complete Unicode scalars, never add replacement characters.
        var bytes = text.utf8.suffix(maximumUTF8Bytes)
        while let first = bytes.first, first & 0xC0 == 0x80 { bytes = bytes.dropFirst() }
        activity.detail = String(decoding: bytes, as: UTF8.self)
        activity.outputTruncated = true
    }

    /// Linear-time longest suffix/prefix match; aggregate events may repeat streamed bytes.
    private static func overlap(_ old: String, _ new: String) -> Int {
        let pattern = Array(new.utf8)
        guard !pattern.isEmpty else { return 0 }
        var prefix = Array(repeating: 0, count: pattern.count)
        for index in 1..<pattern.count {
            var matched = prefix[index - 1]
            while matched > 0 && pattern[index] != pattern[matched] { matched = prefix[matched - 1] }
            if pattern[index] == pattern[matched] { matched += 1 }
            prefix[index] = matched
        }
        var matched = 0
        for byte in old.utf8.suffix(pattern.count) {
            while matched > 0 && (matched == pattern.count || byte != pattern[matched]) { matched = prefix[matched - 1] }
            if byte == pattern[matched] { matched += 1 }
        }
        return matched
    }
}
