/// Shared Library/MCP inventory visibility; attachment storage retains its own access routes.
public enum WorkspaceLibraryVisibility {
    public static func includes(_ path: String) -> Bool {
        path.split(separator: "/", omittingEmptySubsequences: true).first != "Attachments"
    }
}
