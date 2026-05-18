import Foundation
import SwiftData

@Model
final class ConversationSession {
    @Attribute(.unique) var id: UUID
    var scenarioTitle: String
    var levelCEFR: String?
    var startedAt: Date
    var endedAt: Date?
    /// JSON: [{ "speaker": "user|assistant", "text": "...", "timestamp": "..." }]
    var turnsJSON: String
    var reportMD: String?

    init(
        id: UUID = UUID(),
        scenarioTitle: String,
        levelCEFR: String? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        turnsJSON: String = "[]",
        reportMD: String? = nil
    ) {
        self.id = id
        self.scenarioTitle = scenarioTitle
        self.levelCEFR = levelCEFR
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.turnsJSON = turnsJSON
        self.reportMD = reportMD
    }
}
