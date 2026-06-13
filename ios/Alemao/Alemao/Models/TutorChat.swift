import Foundation
import SwiftData
import SwiftUI

// ============================================================
// MARK: - Persisted @Model (transcript as JSON blob, per app convention —
//         mirrors ConversationSession.turnsJSON)
// ============================================================

@Model
final class TutorChat {
    @Attribute(.unique) var id: UUID
    var title: String                 // auto: first user line, truncated
    var levelCEFR: String?            // running level (seeded from User, updated by level_estimate)
    var startedAt: Date
    var lastMessageAt: Date
    /// JSON-encoded [ChatMessage] — full transcript (German lines + attached feedback).
    var messagesJSON: String
    /// JSON-encoded TutorMemory — running learner profile that drives proactive cadence.
    var memoryJSON: String

    init(
        id: UUID = UUID(),
        title: String = "Neues Gespräch",
        levelCEFR: String? = nil,
        startedAt: Date = .now,
        lastMessageAt: Date = .now,
        messagesJSON: String = "[]",
        memoryJSON: String = "{}"
    ) {
        self.id = id
        self.title = title
        self.levelCEFR = levelCEFR
        self.startedAt = startedAt
        self.lastMessageAt = lastMessageAt
        self.messagesJSON = messagesJSON
        self.memoryJSON = memoryJSON
    }

    /// Convenience accessors (decode/encode the blob; safe on failure).
    /// Não são persistidos pelo SwiftData (são computed properties sobre os blobs).
    var messages: [ChatMessage] {
        get { (try? JSONDecoder().decode([ChatMessage].self, from: Data(messagesJSON.utf8))) ?? [] }
        set {
            if let d = try? JSONEncoder().encode(newValue) {
                messagesJSON = String(decoding: d, as: UTF8.self)
            }
        }
    }

    var memory: TutorMemory {
        get { (try? JSONDecoder().decode(TutorMemory.self, from: Data(memoryJSON.utf8))) ?? TutorMemory() }
        set {
            if let d = try? JSONEncoder().encode(newValue) {
                memoryJSON = String(decoding: d, as: UTF8.self)
            }
        }
    }
}

// ============================================================
// MARK: - Transcript item (Codable, stored inside messagesJSON)
// Um elemento por bolha visível. Mensagens do usuário carregam as próprias
// correções, então a aba "Meus erros" e o reload do histórico NÃO precisam
// de uma segunda chamada ao modelo.
// ============================================================

struct ChatMessage: Codable, Identifiable, Hashable {
    var id: UUID
    var role: Role                       // .user | .tutor
    var text_de: String                  // conteúdo em ALEMÃO mostrado na bolha
    var timestamp: Date

    // --- só em mensagens .user (feedback sobre o que ele digitou) ---
    var corrections: [Correction]?       // chips abaixo da bolha do USUÁRIO; nil/[] = turno limpo

    // --- só em mensagens .tutor ---
    var praise_pt: String?               // elogio curto em PT, ex.: "Boa! Acertou o dativo."
    var miniLesson: MiniLesson?          // card de micro-aula proativa; nil na maioria dos turnos
    var suggestedReplies_de: [String]?   // sugestões de resposta tocáveis acima do input

    enum Role: String, Codable { case user, tutor }

    init(
        id: UUID = UUID(),
        role: Role,
        text_de: String,
        timestamp: Date = .now,
        corrections: [Correction]? = nil,
        praise_pt: String? = nil,
        miniLesson: MiniLesson? = nil,
        suggestedReplies_de: [String]? = nil
    ) {
        self.id = id
        self.role = role
        self.text_de = text_de
        self.timestamp = timestamp
        self.corrections = corrections
        self.praise_pt = praise_pt
        self.miniLesson = miniLesson
        self.suggestedReplies_de = suggestedReplies_de
    }

    // Decode resiliente: id e timestamp ausentes recebem defaults (compat futura).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        role = try c.decode(Role.self, forKey: .role)
        text_de = (try? c.decode(String.self, forKey: .text_de)) ?? ""
        timestamp = (try? c.decode(Date.self, forKey: .timestamp)) ?? .now
        corrections = try? c.decodeIfPresent([Correction].self, forKey: .corrections)
        praise_pt = try? c.decodeIfPresent(String.self, forKey: .praise_pt)
        miniLesson = try? c.decodeIfPresent(MiniLesson.self, forKey: .miniLesson)
        suggestedReplies_de = try? c.decodeIfPresent([String].self, forKey: .suggestedReplies_de)
    }
}

// ============================================================
// MARK: - Tutor turn DTO (decodificado direto do JSON do LLM; UM round-trip)
// Resiliente: só `reply_de` é obrigatório. Todo o resto é opcional para que uma
// chave ausente degrade para "só conversa" em vez de crashar o decode. Nenhum
// responseSchema é enviado (a Gemini Developer API rejeita additionalProperties)
// — o formato é descrito apenas no prompt.
// ============================================================

struct TutorTurn: Decodable {
    let reply_de: String                 // a resposta natural em alemão (mantém o papo)
    let praise_pt: String?               // elogio em PT (1 linha); nil quando nada a elogiar
    let corrections: [Correction]?       // 0–3 itens; nil/[] quando o usuário escreveu certo
    let mini_lesson: MiniLesson?         // opcional; obedece às regras de cadência do prompt
    let suggested_replies_de: [String]?  // 1–3 sugestões tocáveis; pode ser nil/[]
    let memory_update: MemoryUpdate?     // leitura corrente do tutor sobre o aluno

    enum CodingKeys: String, CodingKey {
        case reply_de, praise_pt, corrections, mini_lesson, suggested_replies_de, memory_update
    }
}

struct Correction: Codable, Hashable, Identifiable {
    var id: String { (original_de ?? "") + "|" + (corrected_de ?? "") }

    let original_de: String?             // o trecho errado do aluno (verbatim, curto)
    let corrected_de: String?            // o trecho corrigido em alemão
    let category: String?                // TutorMistakeCategory.rawValue
    let explanation_pt: String?          // explicação "aha" em PT (1–2 frases)
    let severity: String?                // "blocking" | "teach" | "polish" (default "teach")

    enum CodingKeys: String, CodingKey {
        case original_de, corrected_de, category, explanation_pt, severity
    }

    var categoryEnum: TutorMistakeCategory { TutorMistakeCategory(rawValue: category ?? "") ?? .grammar }
    var severityEnum: TutorSeverity { TutorSeverity(rawValue: severity ?? "teach") ?? .teach }
}

struct MiniLesson: Codable, Hashable {
    let title_pt: String?                // manchete curta em PT, ex.: "Dativo depois de 'mit'"
    let trigger_pt: String?              // 1 linha em PT: "por que surgiu agora" (o gancho merecido)
    let body_pt: String?                 // explicação em PT (2–4 frases), o momento de aprendizado
    let examples_de: [String]?           // 1–3 frases-exemplo corretas em alemão
    let skill_tag: String?               // id estável, ex.: "case_dativ" (para cadência/anti-repetição)

    var examples: [String] { examples_de ?? [] }
}

/// Leitura evolutiva do aluno feita pelo modelo. Tudo opcional → resiliente a omissão.
struct MemoryUpdate: Codable, Hashable {
    let level_estimate: String?          // estimativa CEFR corrente (A1…C1)
    let recurring_gaps: [String]?        // skill_tags errados repetidamente
    let strengths: [String]?             // skill_tags bem dominados
    let last_taught_skill: String?       // skill_tag ensinado neste turno (nil se nenhum)
}

// ============================================================
// MARK: - Perfil local do aluno (dentro de memoryJSON, nunca enviado cru à UI)
// O cliente é a FONTE DA VERDADE da cadência: turnsSinceLastLesson é incrementado
// pelo cliente (zerado quando uma aula aparece), então mesmo um modelo afoito
// fica limitado pelo que o próximo prompt reporta.
// ============================================================

struct TutorMemory: Codable {
    var levelEstimate: String?
    var recurringGaps: [String] = []     // skill_tags acumulados (union-merge a cada turno)
    var strengths: [String] = []
    var lastTaughtSkill: String?
    var turnsSinceLastLesson: Int = 99   // começa alto para a primeira aula não ser bloqueada

    /// Funde o MemoryUpdate do modelo no perfil local após cada turno.
    /// `lessonSurfaced` reflete o que a UI realmente MOSTROU (após o gate do cliente),
    /// não apenas o que o modelo propôs. `surfacedSkillTag` é o skill_tag da aula que
    /// efetivamente apareceu — a fonte da verdade para o anti-repetição do próximo turno
    /// (o `last_taught_skill` solto do modelo pode vir nil/divergente e não deve sobrescrever).
    mutating func fold(_ update: MemoryUpdate?, lessonSurfaced: Bool, surfacedSkillTag: String?) {
        if let lvl = update?.level_estimate, !lvl.isEmpty { levelEstimate = lvl }
        if let gaps = update?.recurring_gaps {
            recurringGaps = Array(Set(recurringGaps).union(gaps)).sorted()
        }
        if let str = update?.strengths {
            strengths = Array(Set(strengths).union(str)).sorted()
            // Uma habilidade dominada não é mais uma fraqueza.
            recurringGaps.removeAll { strengths.contains($0) }
        }
        if lessonSurfaced {
            lastTaughtSkill = surfacedSkillTag
            turnsSinceLastLesson = 0
        } else {
            turnsSinceLastLesson += 1
        }
    }
}

// ============================================================
// MARK: - Taxonomia de erro — enum PRÓPRIO (não reusar WritingCorrector.ErrorCategory:
// seus 6 casos não têm case/verbForm/lusism). Strings desconhecidas → .grammar.
// Tints reusam tokens de cor existentes em DesignTokens.swift.
// ============================================================

enum TutorMistakeCategory: String, Codable, CaseIterable {
    case grammar        // morfologia/concordância genérica
    case case_ = "case" // Kasus — caso errado (Nom/Akk/Dat/Gen)
    case verbForm       // conjugação, tempo, prefixos separáveis, Partizip
    case wordOrder      // V2, verbo no fim em orações subordinadas
    case vocabulary     // escolha de palavra errada
    case lusism         // Lusismo: calque do PT (falso amigo, calque de regência, gênero puxado)
    case spelling       // Rechtschreibung incl. Groß-/Kleinschreibung
    case register       // du/Sie, formalidade

    var label: String {
        switch self {
        case .grammar:    return "Gramática"
        case .case_:      return "Caso"
        case .verbForm:   return "Verbo"
        case .wordOrder:  return "Ordem"
        case .vocabulary: return "Vocabulário"
        case .lusism:     return "Lusismo"
        case .spelling:   return "Ortografia"
        case .register:   return "Registro"
        }
    }

    /// Reusa tokens semânticos de DesignTokens.swift. Lusism = .danger (maior sinal
    /// para falantes de PT). Todas as cores referenciadas existem no design system.
    var tint: Color {
        switch self {
        case .lusism:                 return .danger             // vermelho — alto sinal
        case .case_, .grammar:        return .warning            // laranja
        case .verbForm:               return .tagIrregular       // laranja variante
        case .wordOrder:              return .genderPlural       // roxo
        case .vocabulary:             return .info               // azul
        case .register:               return .tenseKonjunktivII  // roxo variante
        case .spelling:               return .tagReflexive       // rosa
        }
    }
}

enum TutorSeverity: String, Codable { case blocking, teach, polish }
