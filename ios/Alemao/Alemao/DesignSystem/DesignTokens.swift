import SwiftUI

/// Tokens centralizados do design system do Alemão.
///
/// Princípios:
/// - **Nomes semânticos**, não literais. `Color.tensePraesens` em vez de `.blue`.
/// - **Escala 8pt grid** para spacing. Use múltiplos de 4.
/// - **3 níveis de opacity** (subtle/medium/strong) — não invente outros.
/// - **3 raios padrão**: small (chips), card (default), modal (sheets).
///
/// Adoção é gradual: novos códigos usam tokens; código antigo migra conforme
/// for tocado. Não há urgência em refatorar tudo de uma vez.

// MARK: - Spacing

enum AppSpacing {
    /// 4pt — espaço apertado entre elementos pequenos (badges adjacentes, ícones).
    static let xs: CGFloat = 4
    /// 8pt — padrão para listas e linhas de uma row.
    static let sm: CGFloat = 8
    /// 12pt — separa subseções dentro de um card.
    static let md: CGFloat = 12
    /// 16pt — padding default de página/card. `.padding()` sem args = isto.
    static let lg: CGFloat = 16
    /// 24pt — separa seções principais.
    static let xl: CGFloat = 24
    /// 32pt — pouco usado; topo de tela após Spacer.
    static let xxl: CGFloat = 32
}

// MARK: - Corner Radius

enum AppRadius {
    /// 8pt — chips, capsules pequenas, badges grandes.
    static let small: CGFloat = 8
    /// 12pt — cards e containers padrão.
    static let card: CGFloat = 12
    /// 16pt — modais, sheets, painéis de destaque.
    static let modal: CGFloat = 16
}

// MARK: - Opacity (para backgrounds e overlays)

enum AppOpacity {
    /// 0.06 — backgrounds quase imperceptíveis (cards terciários).
    static let subtle: Double = 0.06
    /// 0.12 — backgrounds visíveis (cards padrão, hover states).
    static let medium: Double = 0.12
    /// 0.20 — pills, badges destacados, accents.
    static let strong: Double = 0.20
}

// MARK: - Cores semânticas

extension Color {
    // ---- Gênero gramatical (substantivos alemães) ----
    /// Azul — usado para `der` (masculino).
    static let genderMasculine = Color.blue
    /// Vermelho — usado para `die` (feminino).
    static let genderFeminine = Color.red
    /// Verde — usado para `das` (neutro).
    static let genderNeuter = Color.green
    /// Roxo — usado para plural na declinação.
    static let genderPlural = Color.purple

    /// Resolve cor a partir do artigo (`der`, `die`, `das`, nil).
    static func forGender(_ article: String?) -> Color {
        switch article?.lowercased() {
        case "der": return .genderMasculine
        case "die": return .genderFeminine
        case "das": return .genderNeuter
        default: return .secondary
        }
    }

    // ---- Tempos verbais ----
    static let tensePraesens = Color.blue
    static let tensePraeteritum = Color.orange
    static let tenseKonjunktivII = Color.purple

    // ---- Feedback ----
    /// Verde para sucesso / correto.
    static let success = Color.green
    /// Vermelho para erro / incorreto / destrutivo.
    static let danger = Color.red
    /// Laranja para warning / quase / atenção.
    static let warning = Color.orange
    /// Azul para info / dica neutra.
    static let info = Color.blue

    // ---- Tags de verbo ----
    static let tagSeparable = Color.purple
    static let tagReflexive = Color.pink
    static let tagIrregular = Color.orange
}

// MARK: - Card style modifier

extension View {
    /// Aplica o estilo de card padrão do app: padding + background com opacidade
    /// + clipShape com raio. Substitui o padrão repetido por toda a UI.
    ///
    /// Uso:
    /// ```swift
    /// VStack { ... }
    ///   .appCard()                          // subtle, card radius
    ///   .appCard(tone: .medium)             // mais visível
    ///   .appCard(tone: .strong, radius: .modal)
    /// ```
    func appCard(
        tone: AppCardTone = .subtle,
        radius: AppCardRadius = .card,
        padding: CGFloat = AppSpacing.lg
    ) -> some View {
        self
            .padding(padding)
            .background(Color.secondary.opacity(tone.value))
            .clipShape(RoundedRectangle(cornerRadius: radius.value))
    }
}

enum AppCardTone {
    case subtle, medium, strong
    var value: Double {
        switch self {
        case .subtle: return AppOpacity.subtle
        case .medium: return AppOpacity.medium
        case .strong: return AppOpacity.strong
        }
    }
}

enum AppCardRadius {
    case small, card, modal
    var value: CGFloat {
        switch self {
        case .small: return AppRadius.small
        case .card: return AppRadius.card
        case .modal: return AppRadius.modal
        }
    }
}

// MARK: - Format helpers (extraídos de duplicações)

extension Int {
    /// Formata um intervalo de dias do SRS: "novo", "5d", "3m".
    /// Substitui a função `formatInterval(_:)` duplicada em 2 telas.
    var srsIntervalLabel: String {
        if self == 0 { return "novo" }
        if self < 30 { return "\(self)d" }
        return "\(self / 30)m"
    }
}
