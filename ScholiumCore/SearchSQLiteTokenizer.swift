import Foundation
import SQLite3
import ScholiumContracts

/// Uses the same native tokenizer and options as search_fts. Foundation's
/// Unicode categories cannot decide what this SQLite build can index.
final class SearchSQLiteTokenizer {
    static let name = "unicode61"
    static let arguments = ["remove_diacritics", "2"]
    static var configuration: String { ([name] + arguments).joined(separator: " ") }

    private let functions: fts5_tokenizer
    private let instance: OpaquePointer

    init(database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT fts5(?1)", -1, &statement, nil) == SQLITE_OK,
            let statement
        else { throw SearchIndexError.sqlite("Could not inspect the Search tokenizer.") }
        var api: UnsafeMutablePointer<fts5_api>?
        let result = withUnsafeMutablePointer(to: &api) { pointer in
            "fts5_api_ptr".withCString { type in
                defer { sqlite3_finalize(statement) }
                let bound = sqlite3_bind_pointer(statement, 1, pointer, type, nil)
                return bound == SQLITE_OK ? sqlite3_step(statement) : bound
            }
        }
        guard result == SQLITE_ROW, let api else {
            throw SearchIndexError.sqlite("The Search tokenizer API is unavailable.")
        }
        var functions = fts5_tokenizer()
        var context: UnsafeMutableRawPointer?
        let found = Self.name.withCString { api.pointee.xFindTokenizer(api, $0, &context, &functions) }
        guard found == SQLITE_OK else { throw SearchIndexError.sqlite("The Search tokenizer is unavailable.") }
        var instance: OpaquePointer?
        let pointers = Self.arguments.map { strdup($0) }
        defer { pointers.forEach { free($0) } }
        guard pointers.allSatisfy({ $0 != nil }) else {
            throw SearchIndexError.sqlite("Could not allocate the Search tokenizer options.")
        }
        var arguments: [UnsafePointer<CChar>?] = pointers.map { $0.map { UnsafePointer<CChar>($0) } }
        let created = arguments.withUnsafeMutableBufferPointer {
            functions.xCreate(context, $0.baseAddress, Int32($0.count), &instance)
        }
        guard created == SQLITE_OK, let instance else {
            throw SearchIndexError.sqlite("Could not initialize the Search tokenizer.")
        }
        self.functions = functions
        self.instance = instance
    }

    deinit { functions.xDelete(instance) }

    func hasTokens(in text: String) throws -> Bool {
        var found = false
        let result = withUnsafeMutablePointer(to: &found) { context in
            text.withCString { bytes in
                functions.xTokenize(instance, context, FTS5_TOKENIZE_QUERY, bytes, Int32(text.utf8.count)) { context, _, _, _, _, _ in
                    context?.assumingMemoryBound(to: Bool.self).pointee = true
                    return SQLITE_OK
                }
            }
        }
        guard result == SQLITE_OK else { throw SearchIndexError.sqlite("Could not tokenize the Search query.") }
        return found
    }
}
