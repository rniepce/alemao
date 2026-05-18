import Foundation
import GRDB

/// Abre `dictionary.sqlite` bundleado em read-only para lookups O(1) de palavras.
final class DictionaryDB {
    static let shared: DictionaryDB? = try? DictionaryDB()

    let dbQueue: DatabaseQueue

    struct Entry: Codable, Hashable {
        let headword: String
        let gender: String?
        let pos: String?
        let translations: [String]
        let examples: [Example]
        let notes: String?
        let source: String
        let sourceBookId: String?
        let sourcePage: Int?

        struct Example: Codable, Hashable {
            let de: String
            let pt: String?
        }
    }

    init() throws {
        let url = Bundle.main.url(
            forResource: "dictionary", withExtension: "sqlite",
            subdirectory: "PrebuiltContent"
        ) ?? Bundle.main.url(forResource: "dictionary", withExtension: "sqlite")
        guard let url else {
            throw LibraryDBError.bundleNotFound
        }
        var config = Configuration()
        config.readonly = true
        self.dbQueue = try DatabaseQueue(path: url.path, configuration: config)
    }

    /// Busca exata pelo headword (case-insensitive).
    func lookup(_ headword: String) throws -> [Entry] {
        let needle = headword.lowercased()
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT headword, gender, pos, translations_json, examples_json,
                       notes, source, source_book_id, source_page
                FROM entries WHERE headword_lower = ?
            """, arguments: [needle])
            return rows.map(Self.rowToEntry)
        }
    }

    /// Busca por prefixo (autocomplete).
    func prefixSearch(_ prefix: String, limit: Int = 20) throws -> [Entry] {
        let needle = prefix.lowercased()
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT headword, gender, pos, translations_json, examples_json,
                       notes, source, source_book_id, source_page
                FROM entries WHERE headword_lower LIKE ? || '%'
                ORDER BY headword_lower LIMIT ?
            """, arguments: [needle, limit])
            return rows.map(Self.rowToEntry)
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries") ?? 0
        }
    }

    private static func rowToEntry(_ row: Row) -> Entry {
        let translations = decodeJSONArray(row["translations_json"] as? String) ?? []
        let examplesRaw = decodeJSONArrayOfDicts(row["examples_json"] as? String) ?? []
        let examples = examplesRaw.compactMap { dict -> Entry.Example? in
            guard let de = dict["de"] as? String else { return nil }
            return Entry.Example(de: de, pt: dict["pt"] as? String)
        }
        return Entry(
            headword: row["headword"],
            gender: row["gender"],
            pos: row["pos"],
            translations: translations,
            examples: examples,
            notes: row["notes"],
            source: row["source"],
            sourceBookId: row["source_book_id"],
            sourcePage: row["source_page"]
        )
    }

    private static func decodeJSONArray(_ s: String?) -> [String]? {
        guard let s, let data = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String]
    }

    private static func decodeJSONArrayOfDicts(_ s: String?) -> [[String: Any]]? {
        guard let s, let data = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }
}
