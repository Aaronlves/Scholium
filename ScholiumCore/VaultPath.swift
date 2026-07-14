import Foundation

/// Derives vault-relative paths after Foundation has normalized filesystem
/// aliases such as macOS's `/tmp` and `/private/tmp` spellings.
///
/// Character-count slicing is unsafe here because a directory enumerator or
/// FSEvents may report a different, but equivalent, spelling from the URL used
/// to open the vault. Component comparison also rejects paths outside the
/// selected vault instead of returning an absolute or partially sliced path.
public enum VaultPath {
    public static func relativePath(for itemURL: URL, in rootURL: URL) -> String? {
        let rootComponents = normalizedComponents(of: rootURL)
        let itemComponents = normalizedComponents(of: itemURL)
        guard itemComponents.count > rootComponents.count,
              Array(itemComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }
        return itemComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static func normalizedComponents(of url: URL) -> [String] {
        url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    }
}
