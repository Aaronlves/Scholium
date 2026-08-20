import Foundation
import ScholiumContracts

private struct ResearchStoreAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Format-neutral validation shared by the portable and machine-local stores.
/// The caller supplies the format-specific error so the stores do not share
/// an error contract merely because their JSON envelopes use the same checks.
enum ResearchStoreCodingValidation {
    static func isValidFingerprint(_ fingerprint: DocumentFingerprint) -> Bool {
        fingerprint.byteCount >= 0
            && fingerprint.sha256.count == 64
            && fingerprint.sha256.unicodeScalars.allSatisfy { scalar in
                ("0"..."9").contains(Character(scalar))
                    || ("a"..."f").contains(Character(scalar))
            }
    }

    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: [String],
        onUnknownField: (String) -> Error
    ) throws {
        let container = try decoder.container(
            keyedBy: ResearchStoreAnyCodingKey.self
        )
        let allowed = Set(allowed)
        if let unknown = container.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw onUnknownField(unknown)
        }
    }

    static func containsAbsolutePath(_ value: String) -> Bool {
        value.split(whereSeparator: { character in
            character.isWhitespace
                || "\"'`()[]{}<>,;".contains(character)
        }).contains { rawToken in
            let token = String(rawToken)
            if token.lowercased().hasPrefix("file://") { return true }
            if token.hasPrefix("/") && token.split(separator: "/").count > 1 {
                return true
            }
            let scalars = Array(token.unicodeScalars)
            return scalars.count >= 3
                && CharacterSet.letters.contains(scalars[0])
                && scalars[1] == ":"
                && (scalars[2] == "\\" || scalars[2] == "/")
        }
    }
}
