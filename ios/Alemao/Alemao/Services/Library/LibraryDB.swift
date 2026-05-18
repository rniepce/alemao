import Foundation
import GRDB

/// Abre `library.sqlite` bundleado em read-only e expõe queries de baixo nível.
///
/// O DB é gerado pelo pipeline Python (Trilha A) e copiado para
/// `Resources/PrebuiltContent/library.sqlite` antes do build via
/// `scripts/sync_content.sh`.
final class LibraryDB {
    static let shared: LibraryDB? = try? LibraryDB()

    let dbQueue: DatabaseQueue

    struct Book: Codable, Hashable {
        let id: String
        let title: String?
        let author: String?
        let type: String
        let levelCEFR: String?
        let language: String?
        let source: String
        let filePath: String?
        let pageCount: Int?

        enum CodingKeys: String, CodingKey {
            case id, title, author, type
            case levelCEFR = "level_cefr"
            case language, source
            case filePath = "file_path"
            case pageCount = "page_count"
        }
    }

    struct ChunkRow {
        let id: String
        let bookId: String
        let bookTitle: String
        let sectionTitle: String?
        let pageStart: Int
        let pageEnd: Int
        let text: String
        let embedding: Data?
    }

    init() throws {
        // Xcode 15+ achata arquivos do Synchronized Root Group no root do bundle.
        // Tentamos primeiro com subdirectory (caso o futuro mude para folder reference)
        // e caímos para o root.
        let url = Bundle.main.url(
            forResource: "library", withExtension: "sqlite",
            subdirectory: "PrebuiltContent"
        ) ?? Bundle.main.url(forResource: "library", withExtension: "sqlite")
        guard let url else {
            throw LibraryDBError.bundleNotFound
        }
        var config = Configuration()
        config.readonly = true
        self.dbQueue = try DatabaseQueue(path: url.path, configuration: config)
    }

    // MARK: - Books

    func allBooks() throws -> [Book] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, title, author, type, level_cefr, language, source, file_path, page_count
                FROM books ORDER BY title
            """)
            return rows.map { row in
                Book(
                    id: row["id"],
                    title: row["title"],
                    author: row["author"],
                    type: row["type"],
                    levelCEFR: row["level_cefr"],
                    language: row["language"],
                    source: row["source"],
                    filePath: row["file_path"],
                    pageCount: row["page_count"]
                )
            }
        }
    }

    func book(id: String) throws -> Book? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT id, title, author, type, level_cefr, language, source, file_path, page_count
                FROM books WHERE id = ?
            """, arguments: [id]) else {
                return nil
            }
            return Book(
                id: row["id"], title: row["title"], author: row["author"],
                type: row["type"], levelCEFR: row["level_cefr"], language: row["language"],
                source: row["source"], filePath: row["file_path"], pageCount: row["page_count"]
            )
        }
    }

    // MARK: - Chunks

    /// FTS5 search com BM25. Retorna [(chunk_id, score)] já ordenado.
    func ftsSearch(query: String, limit: Int = 20) throws -> [(String, Double)] {
        let tokens = query
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        let ftsQuery = tokens.map { "\"\($0)\"" }.joined(separator: " OR ")

        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.id AS id, bm25(chunks_fts) AS rank_score
                FROM chunks_fts JOIN chunks c ON c.rowid = chunks_fts.rowid
                WHERE chunks_fts MATCH ?
                ORDER BY rank_score LIMIT ?
            """, arguments: [ftsQuery, limit])
            return rows.map { ($0["id"], -($0["rank_score"] as Double)) }
        }
    }

    /// Carrega todos os embeddings (id + BLOB). Usado pra busca cosine força-bruta.
    /// Para os volumes esperados (centenas a poucos milhares de chunks), é viável.
    func allEmbeddings() throws -> [(String, [Float])] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, embedding FROM chunks WHERE embedding IS NOT NULL
            """)
            return rows.map { row in
                let blob: Data = row["embedding"]
                return (row["id"], EmbeddingCodec.decode(blob))
            }
        }
    }

    /// Carrega metadata de chunks por IDs.
    func chunks(byIds ids: [String]) throws -> [ChunkRow] {
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        return try dbQueue.read { db in
            let sql = """
                SELECT c.id AS id, c.book_id AS book_id, c.section_title AS section_title,
                       c.page_start AS page_start, c.page_end AS page_end, c.text AS text,
                       c.embedding AS embedding, b.title AS book_title
                FROM chunks c JOIN books b ON b.id = c.book_id
                WHERE c.id IN (\(placeholders))
            """
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(ids))
            return rows.map { row in
                ChunkRow(
                    id: row["id"],
                    bookId: row["book_id"],
                    bookTitle: row["book_title"] ?? "—",
                    sectionTitle: row["section_title"],
                    pageStart: row["page_start"] ?? 0,
                    pageEnd: row["page_end"] ?? 0,
                    text: row["text"],
                    embedding: row["embedding"]
                )
            }
        }
    }

    func chunkCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chunks") ?? 0
        }
    }
}

enum LibraryDBError: LocalizedError {
    case bundleNotFound
    var errorDescription: String? {
        switch self {
        case .bundleNotFound:
            return "library.sqlite não encontrado no bundle. Rode scripts/sync_content.sh."
        }
    }
}

/// (De)serialização de embeddings: float32 little-endian.
enum EmbeddingCodec {
    static func decode(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float32>.size
        return data.withUnsafeBytes { ptr in
            let buffer = ptr.bindMemory(to: Float32.self)
            return Array(buffer.prefix(count))
        }
    }

    static func encode(_ values: [Float]) -> Data {
        var copy = values
        return copy.withUnsafeMutableBytes { Data($0) }
    }
}
