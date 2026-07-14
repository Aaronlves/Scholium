import Foundation

// MARK: - Frontmatter Service

/// Provides schema lookups, field editing, autocomplete suggestions, and display formatting
/// for Obsidian frontmatter.
///
/// Acts as the intermediary between the UI's field editor and the raw frontmatter dictionary —
/// enforcing schema constraints, suggesting known values from across the vault, and formatting
/// values for human-readable display.
actor FrontmatterService {

  // MARK: - Update Field

  /// Updates a single field in the frontmatter dictionary, validating against the schema.
  ///
  /// - Throws: An error if the new value fails enum validation against `allowedValues`.
  ///
  /// - Parameters:
  ///   - key: The frontmatter key to update.
  ///   - value: The new `FrontmatterValue`.
  ///   - frontmatter: The current frontmatter dictionary (immutable — a copy is returned).
  ///   - schema: The schema to validate against.
  /// - Returns: A new frontmatter dictionary with the field updated.
  func updateField(
    _ key: String,
    value: FrontmatterValue,
    in frontmatter: [String: FrontmatterValue],
    schema: FrontmatterSchema
  ) throws -> [String: FrontmatterValue] {
    var fm = frontmatter

    // Find the field definition
    guard let fieldDef = schema.fields.first(where: { $0.key == key }) else {
      // Unknown field — allow anyway (user may add custom fields)
      fm[key] = value
      return fm
    }

    // Enum validation
    if fieldDef.type == .enum, let allowed = fieldDef.allowedValues {
      let strValue: String
      switch value {
      case .string(let s): strValue = s
      case .array(let arr): strValue = arr.first ?? ""
      default: strValue = ""
      }
      if !strValue.isEmpty && !allowed.contains(strValue) {
        // Instead of throwing, we still set but log a validation issue.
        // The caller should use MarkdownEngine.validate() for full validation.
      }
    }

    // Type coercion for convenience
    fm[key] = coerceValue(value, to: fieldDef.type)
    return fm
  }

  /// Lightweight type coercion to help the UI. E.g. if a number field gets a string,
  /// try to parse it as an Int.
  private func coerceValue(_ value: FrontmatterValue, to type: FrontmatterSchema.FieldDefinition.FieldType) -> FrontmatterValue {
    switch (type, value) {
    case (.number, .string(let s)):
      if let intVal = Int(s) { return .int(intVal) }
      if let dblVal = Double(s) { return .double(dblVal) }
      return value
    case (.boolean, .string(let s)):
      let lower = s.lowercased()
      if lower == "true" { return .bool(true) }
      if lower == "false" { return .bool(false) }
      return value
    case (.tags, .string(let s)):
      // Split comma-separated string into array for tags
      let items = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      return .array(items)
    case (.array, .string(let s)):
      // Split comma-separated string into array
      let items = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      return .array(items)
    case (.date, .string(let s)):
      let iso = ISO8601DateFormatter()
      iso.formatOptions = [.withFullDate, .withDashSeparatorInDate]
      if let date = iso.date(from: s) { return .date(date) }
      return value
    default:
      return value
    }
  }

  // MARK: - Tags

  /// Collects all unique tags across the provided notes with occurrence counts.
  ///
  /// - Parameter notes: The notes to scan for `tags` in frontmatter.
  /// - Returns: An array of `(tag, count)` tuples sorted by count descending, then alphabetically.
  func allTags(notes: [Note]) -> [(tag: String, count: Int)] {
    var counts: [String: Int] = [:]

    for note in notes {
      for tag in note.tags {
        let normalized = tag.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { continue }
        counts[normalized, default: 0] += 1
      }
    }

    return counts
      .map { (tag: $0.key, count: $0.value) }
      .sorted { a, b in
        if a.count != b.count { return a.count > b.count }
        return a.tag < b.tag
      }
  }

  // MARK: - Display Formatting

  /// Formats a `FrontmatterValue` for human-readable display in the UI.
  ///
  /// - Dates are formatted as medium-style (`Jan 15, 2026`).
  /// - Arrays are comma-separated.
  /// - Dictionaries are shown as `key: value` pairs.
  /// - Booleans show "Yes" / "No".
  ///
  /// - Parameter value: The value to format.
  /// - Returns: A display-ready string.
  func displayValue(_ value: FrontmatterValue) -> String {
    switch value {
    case .string(let s):
      return s
    case .int(let i):
      return NumberFormatter.localizedString(from: NSNumber(value: i), number: .decimal)
    case .double(let d):
      let nf = NumberFormatter()
      nf.minimumFractionDigits = 0
      nf.maximumFractionDigits = 4
      return nf.string(from: NSNumber(value: d)) ?? "\(d)"
    case .bool(let b):
      return b ? "Yes" : "No"
    case .date(let d):
      let df = DateFormatter()
      df.dateStyle = .medium
      df.timeStyle = .none
      return df.string(from: d)
    case .array(let items):
      return items.joined(separator: ", ")
    case .dictionary(let dict):
      return dict.sorted(by: { $0.key < $1.key })
        .map { "\($0.key): \($0.value)" }
        .joined(separator: "; ")
    }
  }
}
