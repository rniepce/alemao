import Foundation
import WidgetKit

/// Publica snapshots para os widgets via App Group UserDefaults.
///
/// **Setup obrigatório**: o App Group `group.dev.alemao.shared` precisa estar
/// configurado nas Capabilities de AMBOS os targets (Alemao + AlemaoWidgets).
/// O Xcode cria isso ao adicionar a Capability "App Groups" em cada target.
enum WidgetDataPublisher {
    static let appGroupID = "group.dev.alemao.shared"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    enum Key: String {
        case streakDays         = "streak.days"
        case xp                 = "xp.total"
        case dueCardsCount      = "due.cards.count"
        case nextDueCardJSON    = "next.due.card.json"
        case wordOfDayJSON      = "word.of.day.json"
        case lastUpdatedAt      = "snapshot.updatedAt"
    }

    /// Encode helper.
    private static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    /// Atualiza dados disponíveis para o widget. Chame após eventos relevantes
    /// (revisão de card, fim do dia, etc).
    static func publish(snapshot: WidgetSnapshot) {
        guard let d = defaults else { return }
        d.set(snapshot.streakDays, forKey: Key.streakDays.rawValue)
        d.set(snapshot.xp, forKey: Key.xp.rawValue)
        d.set(snapshot.dueCount, forKey: Key.dueCardsCount.rawValue)
        if let card = snapshot.nextDueCard {
            d.set(encode(card), forKey: Key.nextDueCardJSON.rawValue)
        } else {
            d.removeObject(forKey: Key.nextDueCardJSON.rawValue)
        }
        if let word = snapshot.wordOfDay {
            d.set(encode(word), forKey: Key.wordOfDayJSON.rawValue)
        } else {
            d.removeObject(forKey: Key.wordOfDayJSON.rawValue)
        }
        d.set(Date(), forKey: Key.lastUpdatedAt.rawValue)

        // Pede ao WidgetKit pra renderizar os widgets de novo.
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Snapshot serializado pro widget.
struct WidgetSnapshot {
    var streakDays: Int
    var xp: Int
    var dueCount: Int
    var nextDueCard: SharedCard?
    var wordOfDay: SharedCard?
}

/// Versão simplificada e Codable de VocabCard para compartilhamento com widget.
struct SharedCard: Codable, Hashable {
    let headword: String
    let gender: String?
    let translation: String
    let nextReviewISO: String?

    static func from(_ card: VocabCard) -> SharedCard {
        let iso = ISO8601DateFormatter()
        return SharedCard(
            headword: card.headword,
            gender: card.gender,
            translation: card.translation,
            nextReviewISO: iso.string(from: card.nextReviewDate)
        )
    }

    static func from(json: String?) -> SharedCard? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SharedCard.self, from: data)
    }
}
