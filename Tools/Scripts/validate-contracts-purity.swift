import Foundation
import SwiftParser
import SwiftSyntax

// Keep the existing boundary policy, but examine code tokens rather than prose.
// SwiftParser retains executable interpolation expressions while excluding string
// segments, regex patterns and comment trivia from identifier matching.
let forbidden: Set<String> = [
    "FileManager", "URLSession", "SQLite", "FSEvent", "AppKit", "SwiftUI",
    "Combine", "UserDefaults", "NSWorkspace", "NSOpenPanel",
]

guard CommandLine.arguments.count == 2 else {
    print("Usage: validate-contracts-purity.swift <Contracts source directory>")
    exit(64)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
var isDirectory: ObjCBool = false
guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
    print("Contracts purity: source directory is unavailable: \(root.path)")
    exit(66)
}
var failed = false
let enumerator = FileManager.default.enumerator(
    at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles],
    errorHandler: { url, error in
        print("\(url.path): error: \(error.localizedDescription)")
        failed = true
        return false
    })
let sources = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
if sources.isEmpty {
    print("Contracts purity: no Swift sources found in \(root.path)")
    exit(66)
}
for url in sources {
    do {
        let source = try String(contentsOf: url, encoding: .utf8)
        let tree = Parser.parse(source: source)
        guard !tree.hasError else {
            print("\(url.path): error: Contracts purity could not parse Swift source")
            failed = true
            continue
        }
        let locations = SourceLocationConverter(fileName: url.path, tree: tree)
        for token in tree.tokens(viewMode: .sourceAccurate) {
            guard case .identifier(let identifier) = token.tokenKind else { continue }
            let name = identifier.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            guard forbidden.contains(name) else { continue }
            let location = locations.location(for: token.positionAfterSkippingLeadingTrivia)
            print("\(url.path):\(location.line):\(location.column): error: Contracts cannot reference \(name)")
            failed = true
        }
    } catch {
        print("\(url.path): error: \(error.localizedDescription)")
        failed = true
    }
}
if failed { exit(1) }
print("Contracts purity: \(sources.count) Swift files passed")
