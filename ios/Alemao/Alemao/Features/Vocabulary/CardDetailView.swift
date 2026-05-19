import SwiftUI

/// Detalhe de um card de vocabulário. Para verbos, mostra a tabela de conjugação completa.
struct CardDetailView: View {
    let card: VocabCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if card.isVerb, let conj = VerbConjugation.decode(from: card.conjugationJSON) {
                    ConjugationTableView(conjugation: conj)
                } else {
                    nonVerbContent
                }

                srsSection
            }
            .padding()
        }
        .navigationTitle(card.headword)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let g = card.gender {
                    Text(g)
                        .font(.title2.bold())
                        .foregroundStyle(genderColor(g))
                }
                Text(card.headword).font(.title.bold())
                Spacer()
                if let theme = card.theme {
                    Text(theme).font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            if !card.isVerb {
                Text(card.translation).font(.title3).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var nonVerbContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let de = card.exampleDE {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exemplo").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(de).font(.body)
                    if let pt = card.examplePT {
                        Text(pt).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            if let notes = card.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Observação").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(notes).font(.callout).italic()
                }
            }
        }
    }

    private var srsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SRS").font(.subheadline.bold()).foregroundStyle(.secondary)
            HStack {
                statBubble("Intervalo", value: formatInterval(card.interval))
                statBubble("Repetições", value: "\(card.repetitions)")
                statBubble("Próx. revisão", value: card.nextReviewDate, style: .relative)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func statBubble(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.callout.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func statBubble(_ label: String, value: Date, style: Text.DateStyle) -> some View {
        VStack(spacing: 2) {
            Text(value, style: style).font(.caption.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatInterval(_ days: Int) -> String {
        if days == 0 { return "novo" }
        if days < 30 { return "\(days)d" }
        return "\(days / 30)m"
    }

    private func genderColor(_ g: String) -> Color {
        switch g.lowercased() {
        case "der": return .blue
        case "die": return .red
        case "das": return .green
        default: return .secondary
        }
    }
}
