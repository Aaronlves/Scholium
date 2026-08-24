import Foundation
import Testing

@Suite("Interface presentation ownership")
struct InterfacePresentationOwnershipTests {
  @Test("Authored shadow syntax stays inside the closed semantic inventory")
  func authoredShadowInventory() throws {
    let swiftShadows = try occurrenceInventory(
      pattern: #"\.shadow\s*\("#,
      extensions: ["swift"]
    )
    #expect(
      swiftShadows == [
        "Scholium/UI/Components/ScholiumWorkspaceSplitView.swift": 1,
        "Scholium/UI/Foundation/ScholiumDesignSystem.swift": 1,
      ],
      Comment(rawValue: diagnostic(for: swiftShadows))
    )

    let webShadows = try occurrenceInventory(
      pattern: #"box-shadow\s*:"#,
      extensions: ["css", "swift"]
    )
    #expect(
      webShadows == [
        "Scholium/Resources/Editor/editor.css": 2,
        "Scholium/Resources/Editor/previews.css": 1,
        "Scholium/UI/Foundation/ScholiumDesignSystem.swift": 3,
        "Scholium/Views/Note/SafeMarkdownReadWebView.swift": 2,
      ],
      Comment(rawValue: diagnostic(for: webShadows))
    )

    let designSystem = try source(
      at: "Scholium/UI/Foundation/ScholiumDesignSystem.swift"
    )
    let previews = try source(at: "Scholium/Resources/Editor/previews.css")
    let editor = try source(at: "Scholium/Resources/Editor/editor.css")
    let readWebView = try source(
      at: "Scholium/Views/Note/SafeMarkdownReadWebView.swift"
    )

    #expect(
      matchCount(
        pattern: #"box-shadow\s*:\s*var\(--scholium-elevation-"#,
        in: designSystem
      ) == 3
    )
    #expect(
      matchCount(
        pattern: #"box-shadow\s*:\s*var\(--scholium-elevation-"#,
        in: previews
      ) == 1
    )
    #expect(matchCount(pattern: #"box-shadow\s*:\s*inset"#, in: editor) == 2)
    #expect(matchCount(pattern: #"box-shadow\s*:\s*inset"#, in: readWebView) == 2)
  }

  @Test("SwiftUI Button hover has one shared presentation owner")
  func directHoverInventory() throws {
    let swiftUIHover = try occurrenceInventory(
      pattern: #"\.onHover\b"#,
      extensions: ["swift"]
    )
    #expect(
      swiftUIHover == [
        "Scholium/UI/Foundation/ScholiumDesignSystem.swift": 1
      ],
      Comment(rawValue: diagnostic(for: swiftUIHover))
    )

    let webHover = try occurrenceInventory(
      pattern: #":hover\b"#,
      extensions: ["css", "swift"]
    )
    #expect(
      webHover == [
        "Scholium/Resources/Editor/callouts.css": 1,
        "Scholium/UI/Foundation/ScholiumDesignSystem.swift": 3,
      ],
      Comment(rawValue: diagnostic(for: webHover))
    )

    let webPointerEvents = try occurrenceInventory(
      pattern: #"addEventListener\('(pointerover|pointerout|focusin|focusout)'"#,
      extensions: ["swift", "ts"],
      roots: ["Scholium", "WebEditor"]
    )
    #expect(
      webPointerEvents == [
        "WebEditor/reader.ts": 6
      ],
      Comment(rawValue: diagnostic(for: webPointerEvents))
    )
  }

  @Test("Native pointer tracking has exactly two explicit owners")
  func nativePointerTrackingInventory() throws {
    let trackingAreas = try occurrenceInventory(
      pattern: #"NSTrackingArea\s*\("#,
      extensions: ["swift"]
    )
    #expect(
      trackingAreas == [
        "Scholium/UI/Foundation/ScholiumDesignSystem.swift": 1,
        "Scholium/Views/Sidebar/SidebarOutlineRows.swift": 1,
      ],
      Comment(rawValue: diagnostic(for: trackingAreas))
    )

    let eventMonitors = try occurrenceInventory(
      pattern: #"NSEvent\.addLocalMonitorForEvents\s*\("#,
      extensions: ["swift"]
    )
    #expect(
      eventMonitors == [
        "Scholium/UI/Foundation/ScholiumDesignSystem.swift": 1
      ],
      Comment(rawValue: diagnostic(for: eventMonitors))
    )
  }

  @Test("Custom controls do not compound pointer feedback owners")
  func compoundPointerOwnershipInventory() throws {
    let compoundOwners = try pointerFeedbackWrappedCalls(
      to: [
        "ScholiumEditorialIconControl",
        "ScholiumInkIconControl",
      ]
    )
    #expect(
      compoundOwners.isEmpty,
      Comment(rawValue: compoundOwners.sorted().joined(separator: "\n"))
    )
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func source(at relativePath: String) throws -> String {
    try String(
      contentsOf: repositoryRoot.appendingPathComponent(relativePath),
      encoding: .utf8
    )
  }

  private func occurrenceInventory(
    pattern: String,
    extensions: Set<String>,
    roots: [String] = ["Scholium"]
  ) throws -> [String: Int] {
    var inventory: [String: Int] = [:]

    for root in roots {
      let sourceRoot = repositoryRoot.appendingPathComponent(root, isDirectory: true)
      let enumerator = try #require(
        FileManager.default.enumerator(
          at: sourceRoot,
          includingPropertiesForKeys: [.isRegularFileKey],
          options: [.skipsHiddenFiles]
        )
      )
      for case let fileURL as URL in enumerator {
        guard extensions.contains(fileURL.pathExtension) else { continue }
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { continue }
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let count = matchCount(pattern: pattern, in: contents)
        guard count > 0 else { continue }
        inventory[relativePath(for: fileURL)] = count
      }
    }

    return inventory
  }

  private func pointerFeedbackWrappedCalls(
    to componentNames: Set<String>
  ) throws -> Set<String> {
    let scholiumRoot = repositoryRoot.appendingPathComponent(
      "Scholium",
      isDirectory: true
    )
    let enumerator = try #require(
      FileManager.default.enumerator(
        at: scholiumRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    )
    var compoundOwners: Set<String> = []

    for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
      let contents = try String(contentsOf: fileURL, encoding: .utf8)
      let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)

      for (index, lineSlice) in lines.enumerated() {
        let line = String(lineSlice)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard
          let componentName = componentNames.first(where: {
            trimmed.hasPrefix("\($0)(")
          })
        else { continue }

        let ownerIndent = line.prefix { $0 == " " || $0 == "\t" }.count
        var endIndex = index + 1
        while endIndex < lines.count {
          let candidate = String(lines[endIndex])
          let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
          let candidateIndent = candidate.prefix { $0 == " " || $0 == "\t" }.count
          if !candidateTrimmed.isEmpty, candidateIndent < ownerIndent { break }
          endIndex += 1
        }

        let callChain = lines[index..<endIndex].joined(separator: "\n")
        guard callChain.contains(".scholiumContentControlPointerFeedback(") else {
          continue
        }
        let title =
          firstCapture(
            pattern: #"title\s*:\s*\"([^\"]+)\""#,
            in: callChain
          ) ?? "untitled"
        compoundOwners.insert(
          "\(relativePath(for: fileURL)):\(componentName):\(title)"
        )
      }
    }

    return compoundOwners
  }

  private func matchCount(pattern: String, in source: String) -> Int {
    let expression = try? NSRegularExpression(pattern: pattern)
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    return expression?.numberOfMatches(in: source, range: range) ?? 0
  }

  private func firstCapture(pattern: String, in source: String) -> String? {
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    guard
      let match = expression.firstMatch(in: source, range: range),
      let captureRange = Range(match.range(at: 1), in: source)
    else { return nil }
    return String(source[captureRange])
  }

  private func relativePath(for fileURL: URL) -> String {
    fileURL.path.replacingOccurrences(
      of: repositoryRoot.path + "/",
      with: ""
    )
  }

  private func diagnostic(for inventory: [String: Int]) -> String {
    inventory
      .sorted { $0.key < $1.key }
      .map { "\($0.key): \($0.value)" }
      .joined(separator: "\n")
  }
}
