import Foundation
import SQLite3
import ScholiumContracts

// Core-internal SQLite mechanics for the single TriptychSearchIndex owner.
// This file creates no independent index, generation, or transaction owner.

enum SearchSQLiteBinding {
    case text(String)
    case optionalText(String?)
    case int(Int)
    case optionalInt(Int?)
    case blob(Data)
}

final class SearchSQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    // The actor-owned read transaction bounds both reuse and lifetime. Checked-out
    // statements leave this pool, so nested row queries cannot reuse an active cursor.
    private var readStatements: [String: SearchSQLiteStatement]?

    init(path: String) throws {
        if sqlite3_open_v2(
            path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) != SQLITE_OK {
            let message =
                handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "could not open Search v10 database"
            let code = handle.map { sqlite3_extended_errcode($0) }
            if let handle { sqlite3_close(handle) }
            if code.map({ ($0 & 0xFF) == SQLITE_CORRUPT || ($0 & 0xFF) == SQLITE_NOTADB }) == true {
                throw SearchIndexError.corruptDatabase
            }
            throw SearchIndexError.sqlite(message)
        }
        sqlite3_busy_timeout(handle, 3_000)
        sqlite3_progress_handler(
            handle,
            1_000,
            { _ in Task<Never, Never>.isCancelled ? 1 : 0 },
            nil
        )
        try execute("PRAGMA foreign_keys=ON;")
    }

    deinit {
        if let handle {
            sqlite3_progress_handler(handle, 0, nil, nil)
            sqlite3_close(handle)
        }
    }

    var lastInsertRowID: Int { Int(sqlite3_last_insert_rowid(handle)) }

    func execute(_ sql: String, bindings: [SearchSQLiteBinding] = []) throws {
        if bindings.isEmpty {
            var error: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(handle, sql, nil, nil, &error)
            guard result == SQLITE_OK else {
                let message = error.map { String(cString: $0) } ?? lastError
                sqlite3_free(error)
                throw sqliteError(code: result, message: message)
            }
            return
        }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement.handle) }
        try statement.bind(bindings)
        let result = sqlite3_step(statement.handle)
        guard result == SQLITE_DONE else { throw sqliteError(code: result) }
    }

    func query(
        _ sql: String,
        bindings: [SearchSQLiteBinding] = [],
        row: (SearchSQLiteStatement) throws -> Void
    ) throws {
        let statement = try readStatements?.removeValue(forKey: sql) ?? prepare(sql)
        var retained = false
        defer { if !retained { sqlite3_finalize(statement.handle) } }
        try statement.bind(bindings)
        while true {
            let result = sqlite3_step(statement.handle)
            switch result {
            case SQLITE_ROW: try row(statement)
            case SQLITE_DONE:
                if readStatements != nil {
                    let reset = sqlite3_reset(statement.handle)
                    guard reset == SQLITE_OK else { throw sqliteError(code: reset) }
                    let cleared = sqlite3_clear_bindings(statement.handle)
                    guard cleared == SQLITE_OK else { throw sqliteError(code: cleared) }
                    if let replaced = readStatements?.updateValue(statement, forKey: sql) {
                        sqlite3_finalize(replaced.handle)
                    }
                    retained = true
                }
                return
            default: throw sqliteError(code: result)
            }
        }
    }

    func scalarText(_ sql: String) throws -> String? {
        var value: String?
        try query(sql) { value = $0.text(at: 0) }
        return value
    }

    func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try operation()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func readTransaction<Result>(_ operation: () throws -> Result) throws -> Result {
        try execute("BEGIN DEFERRED;")
        readStatements = [:]
        defer {
            for statement in readStatements?.values ?? [String: SearchSQLiteStatement]().values {
                sqlite3_finalize(statement.handle)
            }
            readStatements = nil
        }
        do {
            let result = try operation()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> SearchSQLiteStatement {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw sqliteError(code: result)
        }
        return SearchSQLiteStatement(handle: statement)
    }

    private var lastError: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
    }

    private func sqliteError(code: Int32, message: String? = nil) -> Error {
        if code == SQLITE_INTERRUPT || Task<Never, Never>.isCancelled {
            return CancellationError()
        }
        let extended = handle.map { sqlite3_extended_errcode($0) }
        if extended.map({ ($0 & 0xFF) == SQLITE_CORRUPT || ($0 & 0xFF) == SQLITE_NOTADB }) == true {
            return SearchIndexError.corruptDatabase
        }
        return SearchIndexError.sqlite(message ?? lastError)
    }
}

struct SearchSQLiteStatement {
    let handle: OpaquePointer

    func bind(_ values: [SearchSQLiteBinding]) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32 =
                switch value {
                case .text(let text):
                    text.withCString { sqlite3_bind_text(handle, index, $0, -1, searchSQLiteTransient) }
                case .optionalText(let text):
                    if let text {
                        text.withCString { sqlite3_bind_text(handle, index, $0, -1, searchSQLiteTransient) }
                    } else {
                        sqlite3_bind_null(handle, index)
                    }
                case .int(let value):
                    sqlite3_bind_int64(handle, index, sqlite3_int64(value))
                case .optionalInt(let value):
                    if let value {
                        sqlite3_bind_int64(handle, index, sqlite3_int64(value))
                    } else {
                        sqlite3_bind_null(handle, index)
                    }
                case .blob(let data):
                    data.withUnsafeBytes { bytes in
                        sqlite3_bind_blob64(
                            handle,
                            index,
                            bytes.baseAddress,
                            sqlite3_uint64(data.count),
                            searchSQLiteTransient
                        )
                    }
                }
            guard result == SQLITE_OK else {
                throw SearchIndexError.sqlite("could not bind a Search v10 parameter")
            }
        }
    }

    func text(at column: Int32) -> String? {
        guard let value = sqlite3_column_text(handle, column) else { return nil }
        return String(cString: value)
    }

    func data(at column: Int32) -> Data? {
        guard sqlite3_column_type(handle, column) != SQLITE_NULL else { return nil }
        let count = Int(sqlite3_column_bytes(handle, column))
        guard count > 0 else { return Data() }
        guard let bytes = sqlite3_column_blob(handle, column) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    func int(at column: Int32) -> Int { Int(sqlite3_column_int64(handle, column)) }
    func double(at column: Int32) -> Double { sqlite3_column_double(handle, column) }
    func isNull(at column: Int32) -> Bool { sqlite3_column_type(handle, column) == SQLITE_NULL }
}

private let searchSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
