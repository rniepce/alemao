import Foundation
import SwiftData

/// Card de vocabulário com estado SRS (SM-2).
@Model
final class VocabCard {
    @Attribute(.unique) var id: UUID

    // Conteúdo
    var headword: String
    var gender: String?              // der, die, das
    var translation: String
    var exampleDE: String?
    var examplePT: String?
    var notes: String?

    // Origem (referência lógica ao bundle — não é relacionamento SwiftData)
    var sourceChunkId: String?
    var sourceBookId: String?
    var sourcePage: Int?

    /// Para cards de verbo: JSON com tabelas de conjugação (Präsens, Präteritum,
    /// Perfekt, Konjunktiv II por pessoa). Nil para substantivos/adjetivos.
    /// Estrutura: ver `VerbConjugation` em `Services/Library/SeedVerbLoader.swift`.
    var conjugationJSON: String?

    /// Classe gramatical: "noun" | "verb" | "adj" | "adv" | "prep" | "conj" | nil
    var pos: String?

    /// Tema: "familie", "essen", "reisen", "arbeit", "körper", "zahlen_farben" etc.
    /// Permite filtrar cards na UI.
    var theme: String?

    /// Indica se foi originalmente carregado do bundle (não é card criado pelo usuário).
    var seedSource: String?  // "vocab_seed" | "verb_seed" | nil

    // SRS (SM-2)
    var easeFactor: Double           // 1.3 - 2.5 típico
    var interval: Int                // dias
    var repetitions: Int
    var nextReviewDate: Date
    var lastReviewedAt: Date?

    // Relacionamentos
    var deck: Deck?

    var isVerb: Bool { pos == "verb" && conjugationJSON != nil }

    init(
        id: UUID = UUID(),
        headword: String,
        gender: String? = nil,
        translation: String,
        exampleDE: String? = nil,
        examplePT: String? = nil,
        notes: String? = nil,
        sourceChunkId: String? = nil,
        sourceBookId: String? = nil,
        sourcePage: Int? = nil,
        conjugationJSON: String? = nil,
        pos: String? = nil,
        theme: String? = nil,
        seedSource: String? = nil,
        easeFactor: Double = 2.5,
        interval: Int = 0,
        repetitions: Int = 0,
        nextReviewDate: Date = .now,
        lastReviewedAt: Date? = nil,
        deck: Deck? = nil
    ) {
        self.id = id
        self.headword = headword
        self.gender = gender
        self.translation = translation
        self.exampleDE = exampleDE
        self.examplePT = examplePT
        self.notes = notes
        self.sourceChunkId = sourceChunkId
        self.sourceBookId = sourceBookId
        self.sourcePage = sourcePage
        self.conjugationJSON = conjugationJSON
        self.pos = pos
        self.theme = theme
        self.seedSource = seedSource
        self.easeFactor = easeFactor
        self.interval = interval
        self.repetitions = repetitions
        self.nextReviewDate = nextReviewDate
        self.lastReviewedAt = lastReviewedAt
        self.deck = deck
    }
}
