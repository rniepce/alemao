import Foundation
import SwiftData

/// Carrega `seed_readings.json` do bundle e materializa como `GeneratedReadingEntity`
/// no SwiftData. Faz upsert por `topic` (que serve como chave estável do seed).
///
/// Roda no `task` da ReadingView; barato (índice por topic).
enum SeedReadingLoader {
    struct SeedReading: Decodable {
        let id: String
        let title: String
        let level_cefr: String
        let topic: String
        let body_de: String
        let glossary: [GlossItem]
        let comprehension_questions: [CompQ]
    }
    struct GlossItem: Codable { let de: String; let pt: String }
    struct CompQ: Codable { let question: String; let answer: String }

    enum LoadError: LocalizedError {
        case bundleMissing
        case decode(String)
        var errorDescription: String? {
            switch self {
            case .bundleMissing:
                return "seed_readings.json não encontrado no bundle"
            case .decode(let m):
                return "Falha ao decodificar seed_readings.json: \(m)"
            }
        }
    }

    /// Insere readings do bundle ainda não presentes no SwiftData (chave: `topic`).
    static func load(into context: ModelContext) throws {
        let existing = (try? context.fetch(FetchDescriptor<GeneratedReadingEntity>())) ?? []
        let existingByTopic = Set(existing.map { $0.topic })

        let url = Bundle.main.url(
            forResource: "seed_readings", withExtension: "json",
            subdirectory: "PrebuiltContent"
        ) ?? Bundle.main.url(forResource: "seed_readings", withExtension: "json")

        guard let url else {
            // Sem arquivo de readings é OK — o app funciona sem essa aba pre-populada
            return
        }
        let data = try Data(contentsOf: url)
        let seeds: [SeedReading]
        do {
            seeds = try JSONDecoder().decode([SeedReading].self, from: data)
        } catch {
            throw LoadError.decode(String(describing: error))
        }

        var inserted = 0
        let encoder = JSONEncoder()
        for s in seeds {
            if existingByTopic.contains(s.topic) { continue }
            let entity = GeneratedReadingEntity(
                title: s.title,
                levelCEFR: s.level_cefr,
                topic: s.topic,
                bodyDE: s.body_de,
                glossaryJSON: (try? encoder.encode(s.glossary).asUTF8String) ?? "[]",
                questionsJSON: (try? encoder.encode(s.comprehension_questions).asUTF8String) ?? "[]"
            )
            context.insert(entity)
            inserted += 1
        }
        if inserted > 0 {
            try context.save()
            print("[SeedReadingLoader] +\(inserted) readings inseridos (total: \(existing.count + inserted))")
        }
    }
}

private extension Data {
    var asUTF8String: String { String(data: self, encoding: .utf8) ?? "" }
}
