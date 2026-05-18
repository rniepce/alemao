import Foundation

/// Algoritmo SM-2 (SuperMemo 2) — base do Anki e bibliotecas similares.
///
/// Cada review produz um novo `(interval, repetitions, easeFactor)` baseado
/// na qualidade da resposta. Quality é mapeada das 4 opções da UI:
///   - Errei (Again)   → q = 0
///   - Difícil (Hard)  → q = 3
///   - Bom (Good)      → q = 4
///   - Fácil (Easy)    → q = 5
///
/// Quando q < 3, reinicia-se as repetições.
enum Rating: Int, CaseIterable {
    case again = 0
    case hard = 3
    case good = 4
    case easy = 5

    var label: String {
        switch self {
        case .again: return "Errei"
        case .hard: return "Difícil"
        case .good: return "Bom"
        case .easy: return "Fácil"
        }
    }
}

struct SRSState: Equatable {
    var easeFactor: Double
    var interval: Int        // dias
    var repetitions: Int
    var nextReviewDate: Date

    static func initial(referenceDate: Date = .now) -> SRSState {
        SRSState(easeFactor: 2.5, interval: 0, repetitions: 0, nextReviewDate: referenceDate)
    }
}

enum SRSEngine {
    /// Aplica SM-2 a um estado anterior dado o rating. Retorna o novo estado.
    static func apply(
        _ rating: Rating,
        to current: SRSState,
        now: Date = .now
    ) -> SRSState {
        let q = Double(rating.rawValue)
        var ef = current.easeFactor + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        if ef < 1.3 { ef = 1.3 }

        var reps = current.repetitions
        var interval = current.interval

        if q < 3 {
            // Falhou — reinicia
            reps = 0
            interval = 1
        } else {
            reps += 1
            switch reps {
            case 1: interval = 1
            case 2: interval = 6
            default: interval = Int((Double(current.interval) * ef).rounded())
            }
        }

        let next = Calendar.current.date(byAdding: .day, value: interval, to: now)
            ?? now.addingTimeInterval(TimeInterval(interval) * 86400)

        return SRSState(
            easeFactor: ef,
            interval: interval,
            repetitions: reps,
            nextReviewDate: next
        )
    }
}
