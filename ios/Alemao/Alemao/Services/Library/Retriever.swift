import Foundation

/// Retriever híbrido: FTS5 (BM25) + cosine (embeddings) + Reciprocal Rank Fusion.
///
/// Porta direta do `pipeline/src/alemao_pipeline/retriever.py` para Swift.
final class Retriever {
    struct Hit: Hashable {
        let chunkId: String
        let bookId: String
        let bookTitle: String
        let sectionTitle: String?
        let pageStart: Int
        let pageEnd: Int
        let text: String
        let score: Double
        let ftsRank: Int?
        let denseRank: Int?
    }

    let libraryDB: LibraryDB
    let llmClient: LLMClient

    init(libraryDB: LibraryDB, llmClient: LLMClient) {
        self.libraryDB = libraryDB
        self.llmClient = llmClient
    }

    /// Pipeline completa: query → FTS + dense → RRF → Hits enriquecidos.
    func retrieve(
        query: String,
        limit: Int = 8,
        ftsPool: Int = 20,
        densePool: Int = 20
    ) async throws -> [Hit] {
        // 1. FTS5 (síncrono, rápido)
        let fts = (try? libraryDB.ftsSearch(query: query, limit: ftsPool)) ?? []

        // 2. Embed query + dense search
        let queryVecs = try await llmClient.embed(
            texts: [query],
            taskType: .retrievalQuery,
            dimension: 768
        )
        guard let queryVec = queryVecs.first else {
            return []
        }
        let allEmbeddings = (try? libraryDB.allEmbeddings()) ?? []
        let denseRanked = denseSearch(
            queryVector: queryVec,
            embeddings: allEmbeddings,
            limit: densePool
        )

        // 3. RRF
        let fused = Self.reciprocalRankFusion(rankings: [fts, denseRanked], limit: limit)
        guard !fused.isEmpty else { return [] }

        // 4. Buscar metadata
        let ids = fused.map { $0.id }
        let chunkRows = (try? libraryDB.chunks(byIds: ids)) ?? []
        let byId = Dictionary(uniqueKeysWithValues: chunkRows.map { ($0.id, $0) })

        // 5. Montar Hits na ordem RRF
        var hits: [Hit] = []
        for f in fused {
            guard let row = byId[f.id] else { continue }
            hits.append(Hit(
                chunkId: row.id,
                bookId: row.bookId,
                bookTitle: row.bookTitle,
                sectionTitle: row.sectionTitle,
                pageStart: row.pageStart,
                pageEnd: row.pageEnd,
                text: row.text,
                score: f.score,
                ftsRank: f.positions[0],
                denseRank: f.positions[1]
            ))
        }
        return hits
    }

    // MARK: - Dense

    private func denseSearch(
        queryVector: [Float],
        embeddings: [(String, [Float])],
        limit: Int
    ) -> [(String, Double)] {
        var scored: [(String, Double)] = []
        scored.reserveCapacity(embeddings.count)
        let qn = norm(queryVector)
        guard qn > 0 else { return [] }

        for (id, vec) in embeddings {
            let vn = norm(vec)
            if vn == 0 { continue }
            let dot = Self.dotProduct(queryVector, vec)
            let cos = Double(dot) / (Double(qn) * Double(vn))
            scored.append((id, cos))
        }
        scored.sort { $0.1 > $1.1 }
        return Array(scored.prefix(limit))
    }

    private func norm(_ v: [Float]) -> Float {
        var s: Float = 0
        for x in v { s += x * x }
        return s.squareRoot()
    }

    private static func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        let count = min(a.count, b.count)
        var s: Float = 0
        for i in 0..<count { s += a[i] * b[i] }
        return s
    }

    // MARK: - RRF

    struct FusedResult {
        let id: String
        let score: Double
        let positions: [Int: Int]   // ranking index → 1-based position
    }

    /// Reciprocal Rank Fusion: score(c) = Σ 1 / (k + rank).
    static func reciprocalRankFusion(
        rankings: [[(String, Double)]],
        k: Int = 60,
        limit: Int = 8
    ) -> [FusedResult] {
        var fused: [String: Double] = [:]
        var positions: [String: [Int: Int]] = [:]
        for (rIdx, ranking) in rankings.enumerated() {
            for (pos, item) in ranking.enumerated() {
                let cid = item.0
                fused[cid, default: 0] += 1.0 / Double(k + pos + 1)
                var p = positions[cid] ?? [:]
                p[rIdx] = pos + 1
                positions[cid] = p
            }
        }
        let ordered = fused.sorted { $0.value > $1.value }.prefix(limit)
        return ordered.map { FusedResult(id: $0.key, score: $0.value, positions: positions[$0.key] ?? [:]) }
    }
}
