import SwiftUI

/// Chip de correção mostrado ABAIXO da bolha do usuário (alinhado à direita).
/// Colapsado por padrão (glanceável): categoria + "errado → certo".
/// Tocar expande um card com a explicação em PT.
/// `severity == .blocking` ganha borda vermelha; `.polish` fica esmaecido.
struct CorrectionChip: View {
    let correction: Correction
    @State private var expanded = false

    private var tint: Color { correction.categoryEnum.tint }
    private var isBlocking: Bool { correction.severityEnum == .blocking }
    private var isPolish: Bool { correction.severityEnum == .polish }

    var body: some View {
        VStack(alignment: .trailing, spacing: AppSpacing.xs) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                capsule
            }
            .buttonStyle(.plain)

            if expanded, let explanation = correction.explanation_pt, !explanation.isEmpty {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard(tone: .subtle, radius: .small)
            }
        }
        .opacity(isPolish && !expanded ? 0.7 : 1)
    }

    private var capsule: some View {
        HStack(spacing: AppSpacing.xs) {
            Text(correction.categoryEnum.label)
                .font(.caption2.bold())
                .foregroundStyle(tint)

            if let original = correction.original_de, !original.isEmpty {
                Text(original)
                    .font(.caption2)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            if let corrected = correction.corrected_de, !corrected.isEmpty {
                Text(corrected)
                    .font(.caption2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 5)
        .background(tint.opacity(AppOpacity.subtle))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        .overlay {
            if isBlocking {
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .strokeBorder(Color.danger.opacity(0.6), lineWidth: 1)
            }
        }
    }
}
