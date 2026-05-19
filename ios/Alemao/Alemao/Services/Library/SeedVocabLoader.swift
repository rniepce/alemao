import Foundation
import SwiftData

/// Carrega `seed_vocab.json` do bundle como 6 decks temáticos + cards individuais.
///
/// Estratégia:
/// 1. Para cada theme único no JSON, cria um Deck (se não existir).
/// 2. Para cada palavra, cria um VocabCard com seedSource="vocab_seed" no deck do tema.
///    Idempotente por (headword, deck).
enum SeedVocabLoader {
    struct SeedWord: Decodable {
        let headword: String
        let gender: String?
        let pos: String
        let translation_pt: String
        let example_de: String
        let example_pt: String
        let level_cefr: String
        let theme: String
        let theme_title: String
    }

    static func load(into context: ModelContext) throws {
        guard let url = Bundle.main.url(
            forResource: "seed_vocab", withExtension: "json",
            subdirectory: "PrebuiltContent"
        ) ?? Bundle.main.url(forResource: "seed_vocab", withExtension: "json") else {
            return
        }
        let data = try Data(contentsOf: url)
        let seeds = try JSONDecoder().decode([SeedWord].self, from: data)

        // 1. Decks existentes indexados por nome (que vamos derivar do theme_title)
        let existingDecks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        var decksByName = Dictionary(uniqueKeysWithValues: existingDecks.map { ($0.name, $0) })

        // 2. Cards existentes (qualquer fonte) indexados por (deck name, headword.lowercased)
        let existingCards = (try? context.fetch(FetchDescriptor<VocabCard>())) ?? []
        var cardKeys: Set<String> = []
        for c in existingCards {
            let deckName = c.deck?.name ?? ""
            cardKeys.insert("\(deckName)::\(c.headword.lowercased())")
        }

        var newDecks = 0
        var newCards = 0
        for s in seeds {
            // Resolve deck
            let deckName = s.theme_title
            let deck: Deck
            if let existing = decksByName[deckName] {
                deck = existing
            } else {
                deck = Deck(
                    name: deckName,
                    deckDescription: nil,
                    levelCEFR: s.level_cefr,
                    sourceBookId: nil
                )
                context.insert(deck)
                decksByName[deckName] = deck
                newDecks += 1
            }

            // Idempotência por (deck, headword)
            let key = "\(deckName)::\(s.headword.lowercased())"
            if cardKeys.contains(key) { continue }
            cardKeys.insert(key)

            let card = VocabCard(
                headword: s.headword,
                gender: s.gender,
                translation: s.translation_pt,
                exampleDE: s.example_de,
                examplePT: s.example_pt,
                pos: s.pos,
                theme: s.theme,
                seedSource: "vocab_seed",
                deck: deck
            )
            context.insert(card)
            newCards += 1
        }

        if newDecks > 0 || newCards > 0 {
            try context.save()
            print("[SeedVocabLoader] +\(newDecks) decks, +\(newCards) cards")
        }
    }
}
