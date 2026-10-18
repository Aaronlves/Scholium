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

/// Fingerprint and strict JSON-field validation for Agent Change records.
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
            .first(where: { !allowed.contains($0) })
        {
            throw onUnknownField(unknown)
        }
    }
}
