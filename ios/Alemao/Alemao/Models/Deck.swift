import Foundation
import SwiftData

@Model
final class Deck {
    @Attribute(.unique) var id: UUID
    var name: String
    var deckDescription: String?
    var levelCEFR: String?
    var createdAt: Date
    var sourceBookId: String?   // referência lógica a books.id no bundle

    // Cascata: deletar deck deleta seus cards
    @Relationship(deleteRule: .cascade, inverse: \VocabCard.deck)
    var cards: [VocabCard] = []

    init(
        id: UUID = UUID(),
        name: String,
        deckDescription: String? = nil,
        levelCEFR: String? = nil,
        createdAt: Date = .now,
        sourceBookId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.deckDescription = deckDescription
        self.levelCEFR = levelCEFR
        self.createdAt = createdAt
        self.sourceBookId = sourceBookId
    }
}
