import Foundation
import SQLite3

actor Database {
    private let url: URL
    private var connection: OpaquePointer?

    init(url: URL) {
        self.url = url
    }

    deinit {
        if let connection {
            sqlite3_close(connection)
        }
    }

    func execute(_ sql: String, bind: ((OpaquePointer) throws -> Void)? = nil) throws {
        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bind?(statement)

        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            result = sqlite3_step(statement)
        }

        guard result == SQLITE_DONE else {
            throw makeError(prefix: "SQLite execute failed")
        }
    }

    func executeReturningChanges(_ sql: String, bind: ((OpaquePointer) throws -> Void)? = nil) throws -> Int {
        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bind?(statement)

        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            result = sqlite3_step(statement)
        }

        guard result == SQLITE_DONE else {
            throw makeError(prefix: "SQLite execute failed")
        }

        guard let connection else {
            throw SQLiteError(code: SQLITE_ERROR, message: "SQLite changes failed: database is not open")
        }

        return Int(sqlite3_changes(connection))
    }

    func withTransaction<Value>(_ body: (_ database: isolated Database) throws -> Value) throws -> Value {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let value = try body(self)
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func query<Value>(
        _ sql: String,
        bind: ((OpaquePointer) throws -> Void)? = nil,
        map: (OpaquePointer) throws -> Value
    ) throws -> [Value] {
        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bind?(statement)

        var values: [Value] = []
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                values.append(try map(statement))
            case SQLITE_DONE:
                return values
            default:
                throw makeError(prefix: "SQLite query failed")
            }
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        let connection = try openConnection()
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw makeError(prefix: "SQLite prepare failed")
        }

        return statement
    }

    private func openConnection() throws -> OpaquePointer {
        if let connection {
            return connection
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var openedConnection: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &openedConnection, flags, nil) == SQLITE_OK,
              let openedConnection
        else {
            let message = openedConnection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite open error"
            if let openedConnection {
                sqlite3_close(openedConnection)
            }
            throw SQLiteError(code: SQLITE_CANTOPEN, message: message)
        }

        connection = openedConnection
        try executePragmas(on: openedConnection)
        return openedConnection
    }

    private func executePragmas(on connection: OpaquePointer) throws {
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
    }

    private func makeError(prefix: String) -> SQLiteError {
        guard let connection else {
            return SQLiteError(code: SQLITE_ERROR, message: "\(prefix): database is not open")
        }

        return SQLiteError(
            code: sqlite3_errcode(connection),
            message: "\(prefix): \(String(cString: sqlite3_errmsg(connection)))"
        )
    }
}

struct SQLiteError: Error, Equatable, LocalizedError {
    let code: Int32
    let message: String

    var errorDescription: String? {
        message
    }
}

enum SQLiteValue {
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func bind(_ text: String, to statement: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_text(statement, index, text, -1, transient) == SQLITE_OK else {
            throw SQLiteError(code: SQLITE_MISUSE, message: "Could not bind text at index \(index).")
        }
    }

    static func bind(_ integer: Int, to statement: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_int64(statement, index, Int64(integer)) == SQLITE_OK else {
            throw SQLiteError(code: SQLITE_MISUSE, message: "Could not bind integer at index \(index).")
        }
    }

    static func bind(_ data: Data, to statement: OpaquePointer, at index: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), transient) == SQLITE_OK else {
                throw SQLiteError(code: SQLITE_MISUSE, message: "Could not bind data at index \(index).")
            }
        }
    }

    static func bindNull(to statement: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
            throw SQLiteError(code: SQLITE_MISUSE, message: "Could not bind null at index \(index).")
        }
    }

    static func text(_ statement: OpaquePointer, at index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            return ""
        }

        return String(cString: value)
    }

    static func optionalText(_ statement: OpaquePointer, at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }

        return text(statement, at: index)
    }

    static func integer(_ statement: OpaquePointer, at index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }
}
