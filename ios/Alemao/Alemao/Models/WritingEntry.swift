import Foundation
import SwiftData

@Model
final class WritingEntry {
    @Attribute(.unique) var id: UUID
    var prompt: String?
    var content: String
    var correctionJSON: String?   // JSON estruturado retornado pelo LLM
    var createdAt: Date
    var correctedAt: Date?

    init(
        id: UUID = UUID(),
        prompt: String? = nil,
        content: String,
        correctionJSON: String? = nil,
        createdAt: Date = .now,
        correctedAt: Date? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.content = content
        self.correctionJSON = correctionJSON
        self.createdAt = createdAt
        self.correctedAt = correctedAt
    }
}
