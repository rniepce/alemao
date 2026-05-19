import Foundation
import SwiftData

/// Carrega `seed_verbs.json` do bundle. Cria 1 deck "Verbos" e popula com VocabCards
/// que têm `conjugationJSON` preenchido + `pos = "verb"`.
enum SeedVerbLoader {
    static let deckName: String = "Verbos"

    struct PersonForms: Codable, Hashable {
        let ich: String
        let du: String
        let er: String
        let wir: String
        let ihr: String
        let sie: String
    }

    /// Schema do JSON gerado por pipeline/seed_verbs.py — exatamente o mesmo
    /// formato que `VerbConjugation`, decodificado aqui apenas para reencodar
    /// no VocabCard.conjugationJSON.
    struct SeedVerb: Decodable {
        let id: String
        let infinitive: String
        let translation_pt: String
        let is_irregular: Bool
        let is_separable: Bool
        let is_reflexive: Bool
        let perfekt_aux: String
        let partizip_ii: String
        let praesens: PersonForms
        let praeteritum: PersonForms
        let konjunktiv_ii: PersonForms
        let imperativ_du: String?
        let imperativ_ihr: String?
        let imperativ_sie: String?
        let examples: [VerbExample]?
        let notes_pt: String?
        let level_cefr: String
        let theme: String
    }

    struct VerbExample: Codable, Hashable {
        let de: String
        let pt: String?
    }

    static func load(into context: ModelContext) throws {
        guard let url = Bundle.main.url(
            forResource: "seed_verbs", withExtension: "json",
            subdirectory: "PrebuiltContent"
        ) ?? Bundle.main.url(forResource: "seed_verbs", withExtension: "json") else {
            return
        }
        let data = try Data(contentsOf: url)
        let seeds = try JSONDecoder().decode([SeedVerb].self, from: data)

        // Deck "Verbos" — encontra ou cria
        let decks = (try? context.fetch(
            FetchDescriptor<Deck>(predicate: #Predicate { $0.name == deckName })
        )) ?? []
        let verbDeck: Deck
        if let existing = decks.first {
            verbDeck = existing
        } else {
            verbDeck = Deck(
                name: deckName,
                deckDescription: "60 verbos comuns alemães com tabelas completas de conjugação.",
                levelCEFR: "A1"
            )
            context.insert(verbDeck)
        }

        // Cards de verbo existentes — indexa por infinitivo
        let existingCards = (try? context.fetch(FetchDescriptor<VocabCard>())) ?? []
        let existingInfs = Set(existingCards
            .filter { $0.seedSource == "verb_seed" }
            .map { $0.headword.lowercased() }
        )

        let encoder = JSONEncoder()
        var inserted = 0
        for s in seeds {
            if existingInfs.contains(s.infinitive.lowercased()) { continue }

            // Re-serializa só os campos da tabela (não inclui id/level/theme/etc)
            let conjugation: [String: Any] = [
                "infinitive": s.infinitive,
                "translation_pt": s.translation_pt,
                "is_irregular": s.is_irregular,
                "is_separable": s.is_separable,
                "is_reflexive": s.is_reflexive,
                "perfekt_aux": s.perfekt_aux,
                "partizip_ii": s.partizip_ii,
                "praesens": [
                    "ich": s.praesens.ich, "du": s.praesens.du, "er": s.praesens.er,
                    "wir": s.praesens.wir, "ihr": s.praesens.ihr, "sie": s.praesens.sie,
                ],
                "praeteritum": [
                    "ich": s.praeteritum.ich, "du": s.praeteritum.du, "er": s.praeteritum.er,
                    "wir": s.praeteritum.wir, "ihr": s.praeteritum.ihr, "sie": s.praeteritum.sie,
                ],
                "konjunktiv_ii": [
                    "ich": s.konjunktiv_ii.ich, "du": s.konjunktiv_ii.du, "er": s.konjunktiv_ii.er,
                    "wir": s.konjunktiv_ii.wir, "ihr": s.konjunktiv_ii.ihr, "sie": s.konjunktiv_ii.sie,
                ],
                "imperativ_du": s.imperativ_du as Any,
                "imperativ_ihr": s.imperativ_ihr as Any,
                "imperativ_sie": s.imperativ_sie as Any,
                "examples": (s.examples ?? []).map { ["de": $0.de, "pt": $0.pt as Any] },
                "notes_pt": s.notes_pt as Any,
            ]
            let conjData = (try? JSONSerialization.data(withJSONObject: conjugation, options: [.sortedKeys]))
                ?? Data()
            let conjStr = String(data: conjData, encoding: .utf8) ?? "{}"

            let firstExample = s.examples?.first
            let card = VocabCard(
                headword: s.infinitive,
                gender: nil,
                translation: s.translation_pt,
                exampleDE: firstExample?.de,
                examplePT: firstExample?.pt,
                notes: s.notes_pt,
                conjugationJSON: conjStr,
                pos: "verb",
                theme: s.theme,
                seedSource: "verb_seed",
                deck: verbDeck
            )
            context.insert(card)
            inserted += 1
        }

        if inserted > 0 {
            try context.save()
            print("[SeedVerbLoader] +\(inserted) verbos no deck '\(deckName)'")
        }
        _ = encoder // silenciar warning, manter por simetria
    }
}
