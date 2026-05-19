import Foundation
import SwiftData

/// Carrega `seed_lessons.json` do bundle e materializa como `GeneratedLesson`
/// no SwiftData (uma vez, na primeira execução).
enum SeedLessonLoader {
    struct SeedLesson: Decodable {
        let topic_id: String
        let title: String
        let level_cefr: String
        let summary: String
        let explanation_md: String
        let examples: [SeedExample]
        let exercises: [SeedExercise]
        let citations: [SeedCitation]
    }
    struct SeedExample: Codable { let de: String; let pt: String; let note: String? }
    struct SeedExercise: Codable {
        let question: String
        let answer: String
        let explanation: String?
    }
    struct SeedCitation: Codable {
        let book_id: String
        let book_title: String
        let section_title: String?
        let page_start: Int
        let page_end: Int
        let excerpt: String
    }

    enum LoadError: LocalizedError {
        case bundleMissing
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .bundleMissing:
                return "seed_lessons.json não encontrado em Resources/PrebuiltContent/"
            case .decode(let m):
                return "Falha ao decodificar seed_lessons.json: \(m)"
            }
        }
    }

    /// Carrega ou faz upsert: insere as lições do bundle que ainda não existem
    /// no SwiftData (por `topicId`). Lições existentes são preservadas com seu
    /// estado (caso o usuário tenha alterado / favoritado depois).
    /// Roda em todo app launch — barato (índice por topicId).
    static func load(into context: ModelContext) throws {
        let existingSeeds = (try? context.fetch(
            FetchDescriptor<GeneratedLesson>(predicate: #Predicate { $0.source == "seed" })
        )) ?? []
        let existingByTopic = Dictionary(uniqueKeysWithValues: existingSeeds.map { ($0.topicId, $0) })

        let url = Bundle.main.url(
            forResource: "seed_lessons", withExtension: "json",
            subdirectory: "PrebuiltContent"
        ) ?? Bundle.main.url(forResource: "seed_lessons", withExtension: "json")
        guard let url else {
            throw LoadError.bundleMissing
        }
        let data = try Data(contentsOf: url)
        let seeds: [SeedLesson]
        do {
            seeds = try JSONDecoder().decode([SeedLesson].self, from: data)
        } catch {
            throw LoadError.decode(String(describing: error))
        }

        var insertedCount = 0
        let encoder = JSONEncoder()
        for s in seeds {
            if existingByTopic[s.topic_id] != nil {
                continue  // já existe; preserva estado do usuário
            }
            let lesson = GeneratedLesson(
                topicId: s.topic_id,
                title: s.title,
                levelCEFR: s.level_cefr,
                summary: s.summary,
                explanationMD: s.explanation_md,
                examplesJSON: (try? encoder.encode(s.examples).asUTF8String) ?? "[]",
                exercisesJSON: (try? encoder.encode(s.exercises).asUTF8String) ?? "[]",
                citationsJSON: (try? encoder.encode(s.citations).asUTF8String) ?? "[]",
                generatedAt: .now,
                source: "seed"
            )
            context.insert(lesson)
            insertedCount += 1
        }
        if insertedCount > 0 {
            try context.save()
            print("[SeedLessonLoader] +\(insertedCount) seed lessons inseridas (total: \(existingSeeds.count + insertedCount))")
        }
    }
}

private extension Data {
    var asUTF8String: String { String(data: self, encoding: .utf8) ?? "" }
}
