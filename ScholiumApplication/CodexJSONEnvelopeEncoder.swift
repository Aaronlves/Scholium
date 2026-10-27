import Foundation
import ScholiumContracts

/// Synchronous encoding of the closed transport envelope. Only Foundation
/// JSONEncoder emits JSON bytes; Foundation's existing validity/depth gate
/// runs first, with its temporary Objective-C graph confined to that helper.
enum CodexJSONEnvelopeEncoder {
    static func encode(_ value: [String: MCPJSONValue]) throws -> Data {
        try codexValidateJSONEnvelope(value)
        return try JSONEncoder().encode(CodexIterativeJSONEnvelope(values: value))
    }
}

/// A closed value conversion, leaving UTF-8 escaping and number formatting to
/// Foundation. Validate nonfinite numbers before NSJSONSerialization, whose
/// invalid-object boundary may raise an Objective-C exception.
private func codexFoundationJSONObject(_ values: [String: MCPJSONValue]) throws -> NSMutableDictionary {
    let root = NSMutableDictionary(capacity: values.count)
    var pending: [(value: MCPJSONValue, destination: CodexFoundationJSONDestination)] = []
    for (key, value) in values {
        pending.append((value, .dictionary(root, key)))
    }
    // Building the graph must not consume one Swift call frame per nesting
    // level before Foundation can apply its own JSON-validity check.
    while let (value, destination) = pending.popLast() {
        switch value {
        case .object(let values):
            let object = NSMutableDictionary(capacity: values.count)
            destination.store(object)
            for (key, value) in values {
                pending.append((value, .dictionary(object, key)))
            }
        case .array(let values):
            let array = NSMutableArray(capacity: values.count)
            destination.store(array)
            for value in values.reversed() {
                pending.append((value, .array(array)))
            }
        case .string(let value): destination.store(value)
        case .integer(let value): destination.store(NSNumber(value: value))
        case .double(let value):
            guard value.isFinite else {
                throw EncodingError.invalidValue(
                    value, .init(codingPath: [], debugDescription: "Nonfinite numbers are not valid JSON."))
            }
            destination.store(NSNumber(value: value))
        case .bool(let value): destination.store(NSNumber(value: value))
        case .null: destination.store(NSNull())
        }
    }
    return root
}

private enum CodexFoundationJSONDestination {
    case dictionary(NSMutableDictionary, String)
    case array(NSMutableArray)

    func store(_ value: Any) {
        switch self {
        case .dictionary(let object, let key): object.setObject(value, forKey: key as NSString)
        case .array(let array): array.add(value)
        }
    }
}

/// Foundation validates the complete closed graph before native encoding; no
/// bytes are emitted until the graph satisfies its depth and validity checks.
private func codexValidateJSONEnvelope(_ value: [String: MCPJSONValue]) throws {
    let object = try codexFoundationJSONObject(value)
    guard JSONSerialization.isValidJSONObject(object) else {
        throw EncodingError.invalidValue(
            value, .init(codingPath: [], debugDescription: "The transport envelope is not valid JSON."))
    }
}

/// Walk closed values without invoking MCPJSONValue.encode(to:), Array.encode
/// or Dictionary.encode recursively. All primitive escaping/number formatting
/// and final byte generation remain Foundation JSONEncoder's responsibility.
private struct CodexIterativeJSONEnvelope: Encodable {
    let values: [String: MCPJSONValue]

    func encode(to encoder: any Encoder) throws {
        var frames = [CodexJSONEncodingFrame(value: .object(values), encoder: encoder)]
        // A referencing child commits into its parent on deinit. Release one
        // child at a time, deepest first, while every parent stays retained.
        // The same order applies after any thrown primitive encoding error.
        defer {
            while let frame = frames.popLast() { frame.finish() }
        }
        while let frame = frames.last {
            if let child = try frame.nextChild() {
                frames.append(child)
            } else {
                frames.removeLast().finish()
            }
        }
    }
}

private struct CodexJSONEncodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// This frame owns its container and encoder explicitly. Parents do not own
/// child frames; the stack is their sole lifetime owner. Only one outstanding
/// referencing child exists per parent, because unkeyed.superEncoder() may not
/// reserve its index until that child deinitializes and inserts its value.
private final class CodexJSONEncodingFrame {
    private enum State {
        case pending(MCPJSONValue)
        case keyed(Dictionary<String, MCPJSONValue>.Iterator, KeyedEncodingContainer<CodexJSONEncodingKey>)
        case unkeyed([MCPJSONValue], Int, any UnkeyedEncodingContainer)
        case finished
    }

    private var encoder: (any Encoder)?
    private var state: State

    init(value: MCPJSONValue, encoder: any Encoder) {
        self.encoder = encoder
        state = .pending(value)
    }

    /// Return at most one child, fully committing it before the next call.
    /// Locals retaining containers/encoders end at this synchronous boundary;
    /// finish() itself makes no extra reference copies.
    func nextChild() throws -> CodexJSONEncodingFrame? {
        while true {
            switch state {
            case .pending(let value):
                switch value {
                case .object(let values):
                    state = .keyed(values.makeIterator(), encoder!.container(keyedBy: CodexJSONEncodingKey.self))
                case .array(let values):
                    state = .unkeyed(values, 0, encoder!.unkeyedContainer())
                case .string, .integer, .double, .bool, .null:
                    try Self.encodePrimitive(value, to: encoder!)
                    state = .finished
                    return nil
                }
            case .keyed(var iterator, var container):
                guard let (key, value) = iterator.next() else {
                    state = .finished
                    return nil
                }
                let child = container.superEncoder(forKey: CodexJSONEncodingKey(key))
                state = .keyed(iterator, container)
                return CodexJSONEncodingFrame(value: value, encoder: child)
            case .unkeyed(let values, let index, var container):
                guard index < values.count else {
                    state = .finished
                    return nil
                }
                let child = container.superEncoder()
                state = .unkeyed(values, index + 1, container)
                return CodexJSONEncodingFrame(value: values[index], encoder: child)
            case .finished:
                return nil
            }
        }
    }

    func finish() {
        state = .finished
        encoder = nil
    }

    private static func encodePrimitive(_ value: MCPJSONValue, to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .object, .array:
            preconditionFailure("A structural value must use an iterative encoding frame")
        }
    }
}
