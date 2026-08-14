public enum ScholiumProductIdentity {
    public static let marketingVersion = "0.1.0"
}

/// Immutable distribution coordinates for the independently delivered CLI.
/// The macOS app never inspects, installs, updates, or removes this artifact.
public enum ScholiumCLIDistribution {
    public static let archiveName = "Scholium-CLI-macos.zip"
    public static let downloadURL =
        "https://github.com/Aaronlves/Scholium/releases/latest/download/\(archiveName)"
}
