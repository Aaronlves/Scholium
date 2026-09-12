import Foundation
import ScholiumContracts

func sourceFixture(_ source: String, fields: [String: YAMLValue]?) -> String {
    guard let fields, !fields.isEmpty else { return source }
    func json(_ value: YAMLValue) -> Any {
        switch value {
        case .string(let x): x
        case .integer(let x): x
        case .double(let x): x
        case .boolean(let x): x
        case .null: NSNull()
        case .array(let x): x.map(json)
        case .object(let x): x.mapValues(json)
        }
    }
    let lines =
        fields.sorted { $0.key < $1.key }.map { key, value in
            let data = try! JSONSerialization.data(withJSONObject: json(value), options: [.fragmentsAllowed, .sortedKeys])
            return key + ": " + String(decoding: data, as: UTF8.self)
        }.joined(separator: "\n") + "\n"
    let document = NoteDocument(relativePath: "Fixture.md", rawContent: source)
    if let yaml = document.rawFrontmatter {
        return "---\n" + yaml + (yaml.hasSuffix("\n") ? "" : "\n") + lines + "---\n" + document.body
    }
    return "---\n" + lines + "---\n" + source
}
