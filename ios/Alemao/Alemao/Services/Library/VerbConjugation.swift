import Foundation

/// Decodifica o `conjugationJSON` de um VocabCard em estrutura tipada.
/// Espelha o schema produzido por `pipeline/seed_verbs.py`.
struct VerbConjugation: Codable, Hashable {
    var infinitive: String
    var translation_pt: String
    var is_irregular: Bool
    var is_separable: Bool
    var is_reflexive: Bool
    var perfekt_aux: String          // "haben" ou "sein"
    var partizip_ii: String
    var praesens: PersonForms
    var praeteritum: PersonForms
    var konjunktiv_ii: PersonForms
    var imperativ_du: String?
    var imperativ_ihr: String?
    var imperativ_sie: String?
    var examples: [Example] = []
    var notes_pt: String?

    struct PersonForms: Codable, Hashable {
        var ich: String
        var du: String
        var er: String          // er/sie/es
        var wir: String
        var ihr: String
        var sie: String         // sie pl. = Sie formal

        func form(for person: Person) -> String {
            switch person {
            case .ich: return ich
            case .du: return du
            case .erSieEs: return er
            case .wir: return wir
            case .ihr: return ihr
            case .sieSie: return sie
            }
        }
    }

    struct Example: Codable, Hashable {
        var de: String
        var pt: String?
    }

    enum Person: String, CaseIterable, Identifiable {
        case ich, du, erSieEs, wir, ihr, sieSie
        var id: String { rawValue }
        var label: String {
            switch self {
            case .ich: return "ich"
            case .du: return "du"
            case .erSieEs: return "er/sie/es"
            case .wir: return "wir"
            case .ihr: return "ihr"
            case .sieSie: return "sie/Sie"
            }
        }
    }

    enum Tense: String, CaseIterable, Identifiable {
        case praesens, praeteritum, konjunktivII

        var id: String { rawValue }
        var label: String {
            switch self {
            case .praesens: return "Präsens"
            case .praeteritum: return "Präteritum"
            case .konjunktivII: return "Konjunktiv II"
            }
        }
    }

    func forms(for tense: Tense) -> PersonForms {
        switch tense {
        case .praesens: return praesens
        case .praeteritum: return praeteritum
        case .konjunktivII: return konjunktiv_ii
        }
    }

    /// Decodifica de JSON string.
    static func decode(from json: String?) -> VerbConjugation? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VerbConjugation.self, from: data)
    }
}
