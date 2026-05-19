import Foundation

/// **DUPLICATA INTENCIONAL** dos tipos compartilhados.
///
/// Widget extensions são módulos separados — não podem importar tipos do app
/// principal sem virar dor de cabeça com framework targets. Mantemos versões
/// pequenas e copy-paste-friendly aqui.
///
/// Mantenha sincronizado com `Alemao/Services/Widgets/WidgetDataPublisher.swift`.

enum WidgetKeys {
    static let appGroupID = "group.dev.alemao.shared"
    static let streakDays = "streak.days"
    static let xp = "xp.total"
    static let dueCardsCount = "due.cards.count"
    static let nextDueCardJSON = "next.due.card.json"
    static let wordOfDayJSON = "word.of.day.json"
    static let lastUpdatedAt = "snapshot.updatedAt"
}

struct WidgetCard: Codable, Hashable {
    let headword: String
    let gender: String?
    let translation: String
    let nextReviewISO: String?
}

enum WidgetStore {
    static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetKeys.appGroupID)
    }

    static func streakDays() -> Int { defaults?.integer(forKey: WidgetKeys.streakDays) ?? 0 }
    static func xp() -> Int { defaults?.integer(forKey: WidgetKeys.xp) ?? 0 }
    static func dueCount() -> Int { defaults?.integer(forKey: WidgetKeys.dueCardsCount) ?? 0 }

    static func wordOfDay() -> WidgetCard? {
        decode(defaults?.string(forKey: WidgetKeys.wordOfDayJSON))
    }

    static func nextDueCard() -> WidgetCard? {
        decode(defaults?.string(forKey: WidgetKeys.nextDueCardJSON))
    }

    private static func decode(_ json: String?) -> WidgetCard? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WidgetCard.self, from: data)
    }
}
