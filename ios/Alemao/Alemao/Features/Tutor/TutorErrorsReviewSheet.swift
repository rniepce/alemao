import SwiftUI

/// "Meus erros": achata todas as correções persistidas na conversa, agrupadas por
/// categoria. Zero chamada ao LLM — um log de estudo grátis a partir do histórico.
struct TutorErrorsReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let messages: [ChatMessage]

    /// Correções agrupadas por categoria, na ordem de CaseIterable.
    private var grouped: [(category: TutorMistakeCategory, items: [Correction])] {
        let all = messages.flatMap { $0.corrections ?? [] }
        var byCategory: [TutorMistakeCategory: [Correction]] = [:]
        for correction in all {
            byCategory[correction.categoryEnum, default: []].append(correction)
        }
        return TutorMistakeCategory.allCases.compactMap { category in
            guard let items = byCategory[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }

    private var totalCount: Int {
        messages.reduce(0) { $0 + ($1.corrections?.count ?? 0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if totalCount == 0 {
                    ContentUnavailableView(
                        "Nenhuma correção ainda",
                        systemImage: "checkmark.seal",
                        description: Text("Continue conversando — suas correções aparecem aqui para revisar.")
                    )
                } else {
                    List {
                        ForEach(grouped, id: \.category) { group in
                            Section {
                                ForEach(Array(group.items.enumerated()), id: \.offset) { _, correction in
                                    errorCard(correction)
                                }
                            } header: {
                                HStack {
                                    Text(group.category.label)
                                        .foregroundStyle(group.category.tint)
                                    Spacer()
                                    Text("\(group.items.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Meus erros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pronto") { dismiss() }
                }
            }
        }
    }

    private func errorCard(_ correction: Correction) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                if let original = correction.original_de, !original.isEmpty {
                    Text(original)
                        .font(.callout)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                if let corrected = correction.corrected_de, !corrected.isEmpty {
                    Text(corrected).font(.callout.bold())
                }
            }
            if let explanation = correction.explanation_pt, !explanation.isEmpty {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
