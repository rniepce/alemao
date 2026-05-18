import Foundation
import SwiftData

/// Lição gerada pelo LLM (sob demanda ou pré-bundleada como seed).
@Model
final class GeneratedLesson {
    @Attribute(.unique) var id: UUID
    var topicId: String
    var title: String
    var levelCEFR: String
    var summary: String
    var explanationMD: String
    /// JSON serializado: [{ "de": "...", "pt": "...", "note": "..." }]
    var examplesJSON: String
    /// JSON serializado: [{ "question": "...", "answer": "...", "explanation": "..." }]
    var exercisesJSON: String
    /// JSON serializado: [{ "book_id": "...", "book_title": "...", "section_title": "...",
    ///                       "page_start": N, "page_end": N, "excerpt": "..." }]
    var citationsJSON: String
    var generatedAt: Date
    var source: String   // "seed" (vindo do bundle) ou "on-demand"

    init(
        id: UUID = UUID(),
        topicId: String,
        title: String,
        levelCEFR: String,
        summary: String = "",
        explanationMD: String = "",
        examplesJSON: String = "[]",
        exercisesJSON: String = "[]",
        citationsJSON: String = "[]",
        generatedAt: Date = .now,
        source: String = "on-demand"
    ) {
        self.id = id
        self.topicId = topicId
        self.title = title
        self.levelCEFR = levelCEFR
        self.summary = summary
        self.explanationMD = explanationMD
        self.examplesJSON = examplesJSON
        self.exercisesJSON = exercisesJSON
        self.citationsJSON = citationsJSON
        self.generatedAt = generatedAt
        self.source = source
    }
}
