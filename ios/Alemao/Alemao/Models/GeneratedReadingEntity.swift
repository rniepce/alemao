import Foundation
import SwiftData

/// Texto de leitura gerado sob demanda (Fase 9). Salvo para revisita.
@Model
final class GeneratedReadingEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var levelCEFR: String
    var topic: String
    var bodyDE: String
    /// JSON: [{"de": "...", "pt": "..."}]
    var glossaryJSON: String
    /// JSON: [{"question": "...", "answer": "..."}]
    var questionsJSON: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        levelCEFR: String,
        topic: String,
        bodyDE: String,
        glossaryJSON: String = "[]",
        questionsJSON: String = "[]",
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.levelCEFR = levelCEFR
        self.topic = topic
        self.bodyDE = bodyDE
        self.glossaryJSON = glossaryJSON
        self.questionsJSON = questionsJSON
        self.createdAt = createdAt
    }
}
