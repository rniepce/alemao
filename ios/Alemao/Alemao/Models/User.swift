import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var id: UUID
    /// Sign in with Apple `userIdentifier` — estável entre dispositivos para o mesmo Apple ID.
    /// É a chave canônica para identificar o usuário; sobrevive a reinstalações.
    var appleUserIdentifier: String?
    /// Email vindo do Sign in with Apple (pode ser email-relay da Apple).
    /// Só vem na PRIMEIRA autenticação; logins subsequentes não retornam.
    var email: String?
    var displayName: String
    var levelCEFR: String?           // A1, A2, B1, B2, C1, C2
    var nativeLanguage: String       // ISO code: "pt", "en", ...
    var streakDays: Int
    var xp: Int
    var lastActiveAt: Date?
    var createdAt: Date
    var preferencesJSON: String?     // JSON livre para preferências futuras

    init(
        id: UUID = UUID(),
        appleUserIdentifier: String? = nil,
        email: String? = nil,
        displayName: String = "",
        levelCEFR: String? = nil,
        nativeLanguage: String = "pt",
        streakDays: Int = 0,
        xp: Int = 0,
        lastActiveAt: Date? = nil,
        createdAt: Date = .now,
        preferencesJSON: String? = nil
    ) {
        self.id = id
        self.appleUserIdentifier = appleUserIdentifier
        self.email = email
        self.displayName = displayName
        self.levelCEFR = levelCEFR
        self.nativeLanguage = nativeLanguage
        self.streakDays = streakDays
        self.xp = xp
        self.lastActiveAt = lastActiveAt
        self.createdAt = createdAt
        self.preferencesJSON = preferencesJSON
    }
}
