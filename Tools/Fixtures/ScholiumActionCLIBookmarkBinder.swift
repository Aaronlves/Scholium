import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("Usage: bookmark-binder <source> <output>\n".utf8)
    )
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
guard sourceURL.startAccessingSecurityScopedResource() else {
    FileHandle.standardError.write(Data("Source access was not granted.\n".utf8))
    exit(77)
}
defer { sourceURL.stopAccessingSecurityScopedResource() }

let bookmark = try sourceURL.bookmarkData(
    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
    includingResourceValuesForKeys: [
        .fileResourceIdentifierKey,
        .isRegularFileKey,
    ],
    relativeTo: nil
)
try bookmark.write(to: outputURL, options: .atomic)
