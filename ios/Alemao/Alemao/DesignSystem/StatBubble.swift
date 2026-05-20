import SwiftUI

/// Componente reutilizável para mostrar uma métrica curta (valor + label).
///
/// Substitui 3 implementações distintas (`statBubble` em HomeView,
/// ConjugationQuizView e CardDetailView).
///
/// Uso:
/// ```swift
/// StatBubble(value: "120", label: "verbos")
/// StatBubble(value: "80%", label: "taxa", tint: .success)
/// StatBubble(date: card.nextReviewDate, label: "próxima revisão")
/// ```
struct StatBubble: View {
    let value: AnyView
    let label: String
    let tint: Color?

    init(value: String, label: String, tint: Color? = nil) {
        self.value = AnyView(
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint ?? .primary)
        )
        self.label = label
        self.tint = tint
    }

    /// Variante para datas relativas ("em 3 dias", "agora", etc).
    init(date: Date, style: Text.DateStyle = .relative, label: String) {
        self.value = AnyView(
            Text(date, style: style)
                .font(.caption.monospacedDigit())
        )
        self.label = label
        self.tint = nil
    }

    var body: some View {
        VStack(spacing: 2) {
            value
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.sm)
        .background((tint ?? Color.secondary).opacity(AppOpacity.subtle))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
    }
}

#Preview {
    HStack {
        StatBubble(value: "12", label: "acertos", tint: .success)
        StatBubble(value: "3", label: "erros", tint: .danger)
        StatBubble(value: "80%", label: "taxa", tint: .info)
        StatBubble(value: "15", label: "total")
    }
    .padding()
}
