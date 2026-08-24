import Foundation
import SQLite3

struct AppleBooksImportResult {
    let annotations: [EPUBAnnotation]
    let readingProgress: Double?
    let bookTitle: String
}

enum AppleBooksImporter {
    static func loadAnnotations(
        epubIdentifiers: [String],
        title: String?
    ) throws -> AppleBooksImportResult {
        let databases = try databaseURLs()
        let library = try ReadOnlySQLiteDatabase(url: databases.library)
        guard let asset = try findAsset(
            in: library,
            identifiers: normalizedIdentifiers(epubIdentifiers),
            title: title
        ) else {
            throw ImportError.bookNotFound
        }

        let annotationDatabase = try ReadOnlySQLiteDatabase(url: databases.annotations)
        let annotations = try readAnnotations(in: annotationDatabase, assetID: asset.id)
        return AppleBooksImportResult(
            annotations: annotations,
            readingProgress: asset.progress,
            bookTitle: asset.title
        )
    }

    private static func databaseURLs() throws -> (library: URL, annotations: URL) {
        let documents = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/com.apple.iBooksX/Data/Documents", isDirectory: true)
        let libraryDirectory = documents.appendingPathComponent("BKLibrary", isDirectory: true)
        let annotationDirectory = documents.appendingPathComponent("AEAnnotation", isDirectory: true)
        let manager = FileManager.default

        let library = try manager.contentsOfDirectory(
            at: libraryDirectory,
            includingPropertiesForKeys: nil
        ).first {
            $0.lastPathComponent.hasPrefix("BKLibrary-") && $0.pathExtension == "sqlite"
        }
        let annotations = try manager.contentsOfDirectory(
            at: annotationDirectory,
            includingPropertiesForKeys: nil
        ).first {
            $0.lastPathComponent.hasPrefix("AEAnnotation_") && $0.pathExtension == "sqlite"
        }
        guard let library, let annotations else { throw ImportError.databaseNotFound }
        return (library, annotations)
    }

    private static func normalizedIdentifiers(_ identifiers: [String]) -> [String] {
        var result: [String] = []
        for identifier in identifiers {
            let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            result.append(trimmed)
            if trimmed.lowercased().hasPrefix("urn:uuid:") {
                result.append(String(trimmed.dropFirst("urn:uuid:".count)))
            }
        }
        return Array(Set(result))
    }

    private static func findAsset(
        in database: ReadOnlySQLiteDatabase,
        identifiers: [String],
        title: String?
    ) throws -> (id: String, progress: Double?, title: String)? {
        let identifierSQL = """
        SELECT ZASSETID, ZREADINGPROGRESS, ZTITLE
        FROM ZBKLIBRARYASSET
        WHERE lower(ZEPUBID) = lower(?) OR lower(ZASSETID) = lower(?)
        LIMIT 1
        """
        for identifier in identifiers {
            if let row = try database.firstRow(sql: identifierSQL, bindings: [identifier, identifier]) {
                return asset(from: row)
            }
        }
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleanTitle.isEmpty else { return nil }
        let titleSQL = """
        SELECT ZASSETID, ZREADINGPROGRESS, ZTITLE
        FROM ZBKLIBRARYASSET
        WHERE lower(ZTITLE) = lower(?)
        LIMIT 1
        """
        guard let row = try database.firstRow(sql: titleSQL, bindings: [cleanTitle]) else { return nil }
        return asset(from: row)
    }

    private static func asset(from row: SQLiteRow) -> (id: String, progress: Double?, title: String)? {
        guard let id = row.text(at: 0) else { return nil }
        return (id, row.double(at: 1), row.text(at: 2) ?? "Livro")
    }

    private static func readAnnotations(
        in database: ReadOnlySQLiteDatabase,
        assetID: String
    ) throws -> [EPUBAnnotation] {
        let sql = """
        SELECT ZANNOTATIONUUID, ZANNOTATIONSELECTEDTEXT, ZANNOTATIONNOTE,
               ZANNOTATIONSTYLE, ZANNOTATIONCREATIONDATE
        FROM ZAEANNOTATION
        WHERE ZANNOTATIONASSETID = ?
          AND COALESCE(ZANNOTATIONDELETED, 0) = 0
          AND ZANNOTATIONTYPE = 2
          AND COALESCE(ZANNOTATIONSELECTEDTEXT, '') <> ''
        ORDER BY ZANNOTATIONCREATIONDATE
        """
        return try database.rows(sql: sql, bindings: [assetID]).compactMap { row in
            guard let rawID = row.text(at: 0),
                  let id = UUID(uuidString: rawID),
                  let quote = row.text(at: 1)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !quote.isEmpty else { return nil }
            let note = row.text(at: 2)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let timestamp = row.double(at: 4) ?? 0
            return EPUBAnnotation(
                id: id,
                quote: quote,
                note: note?.isEmpty == false ? note : nil,
                color: highlightColor(for: row.integer(at: 3)),
                createdAt: Date(timeIntervalSinceReferenceDate: timestamp)
            )
        }
    }

    private static func highlightColor(for appleStyle: Int?) -> EPUBHighlightColor {
        switch appleStyle {
        case 1: return .green
        case 2: return .blue
        case 4: return .pink
        case 5: return .purple
        default: return .yellow
        }
    }
}

private enum ImportError: LocalizedError {
    case databaseNotFound
    case bookNotFound
    case database(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "Não encontrei a biblioteca local do Apple Books neste Mac."
        case .bookNotFound:
            return "Este EPUB não foi encontrado na biblioteca do Apple Books."
        case .database(let message):
            return "Não foi possível ler as anotações do Apple Books: \(message)"
        }
    }
}

private struct SQLiteRow {
    let cells: [SQLiteCell]

    func text(at index: Int32) -> String? {
        guard cells.indices.contains(Int(index)),
              case .text(let value) = cells[Int(index)] else { return nil }
        return value
    }

    func double(at index: Int32) -> Double? {
        guard cells.indices.contains(Int(index)) else { return nil }
        switch cells[Int(index)] {
        case .double(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }

    func integer(at index: Int32) -> Int? {
        guard cells.indices.contains(Int(index)) else { return nil }
        switch cells[Int(index)] {
        case .integer(let value): return Int(value)
        case .double(let value): return Int(value)
        default: return nil
        }
    }
}

private enum SQLiteCell {
    case null
    case text(String)
    case double(Double)
    case integer(Int64)
}

private final class ReadOnlySQLiteDatabase {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "erro desconhecido"
            if let handle { sqlite3_close(handle) }
            throw ImportError.database(message)
        }
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func firstRow(sql: String, bindings: [String]) throws -> SQLiteRow? {
        var result: [SQLiteRow] = []
        try query(sql: sql, bindings: bindings) { row in
            if result.isEmpty { result.append(row) }
        }
        return result.first
    }

    func rows(sql: String, bindings: [String]) throws -> [SQLiteRow] {
        var result: [SQLiteRow] = []
        try query(sql: sql, bindings: bindings) { result.append($0) }
        return result
    }

    private func query(
        sql: String,
        bindings: [String],
        receive: (SQLiteRow) -> Void
    ) throws {
        guard let handle else { throw ImportError.database("banco fechado") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ImportError.database(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            let status = value.withCString {
                sqlite3_bind_text(statement, Int32(offset + 1), $0, -1, transient)
            }
            guard status == SQLITE_OK else {
                throw ImportError.database(String(cString: sqlite3_errmsg(handle)))
            }
        }
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_ROW {
                let cells = (0..<sqlite3_column_count(statement)).map { index -> SQLiteCell in
                    switch sqlite3_column_type(statement, index) {
                    case SQLITE_INTEGER:
                        return .integer(sqlite3_column_int64(statement, index))
                    case SQLITE_FLOAT:
                        return .double(sqlite3_column_double(statement, index))
                    case SQLITE_TEXT:
                        guard let value = sqlite3_column_text(statement, index) else { return .null }
                        return .text(String(cString: value))
                    default:
                        return .null
                    }
                }
                receive(SQLiteRow(cells: cells))
            } else if status == SQLITE_DONE {
                break
            } else {
                throw ImportError.database(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }
}
