import AVFoundation
import SwiftData
import SwiftUI

/// Sessão de revisão: itera cards aplicando SM-2.
struct ReviewSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Cards a serem revisados (snapshot inicial — não reativo a inserts).
    let cards: [VocabCard]

    @State private var index: Int = 0
    @State private var showAnswer: Bool = false
    @State private var reviewedCount: Int = 0

    private var currentCard: VocabCard? {
        guard index < cards.count else { return nil }
        return cards[index]
    }

    var body: some View {
        VStack(spacing: 16) {
            // Progress
            ProgressView(value: Double(reviewedCount), total: Double(max(cards.count, 1)))
                .padding(.horizontal)

            if let card = currentCard {
                cardView(card)
            } else {
                ContentUnavailableView(
                    "Sessão concluída",
                    systemImage: "checkmark.seal.fill",
                    description: Text("Você revisou \(reviewedCount) cards.")
                )
                Button("Voltar") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .navigationTitle("Revisão")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func cardView(_ card: VocabCard) -> some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    if let g = card.gender {
                        Text(g)
                            .font(.title2.bold())
                            .foregroundStyle(genderColor(g))
                    }
                    Text(card.headword)
                        .font(.system(size: 36, weight: .bold))
                }
                Button {
                    speak(card.headword)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            if showAnswer {
                if card.isVerb,
                   let conj = VerbConjugation.decode(from: card.conjugationJSON) {
                    ScrollView {
                        ConjugationTableView(conjugation: conj)
                            .padding()
                    }
                    .frame(maxHeight: 380)
                } else {
                    VStack(spacing: 8) {
                        Text(card.translation)
                            .font(.title3)
                        if let ex = card.exampleDE {
                            Text(ex).font(.callout).foregroundStyle(.secondary)
                            if let ept = card.examplePT {
                                Text(ept).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding()
                }
            }

            Spacer()

            if showAnswer {
                HStack(spacing: 12) {
                    ForEach(Rating.allCases, id: \.self) { rating in
                        Button {
                            apply(rating, to: card)
                        } label: {
                            VStack(spacing: 2) {
                                Text(rating.label)
                                    .font(.callout.bold())
                                Text(intervalLabel(for: rating, card: card))
                                    .font(.caption2.monospacedDigit())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(color(for: rating))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            } else {
                Button {
                    showAnswer = true
                } label: {
                    Text("Mostrar resposta")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    private func apply(_ rating: Rating, to card: VocabCard) {
        let oldState = SRSState(
            easeFactor: card.easeFactor,
            interval: card.interval,
            repetitions: card.repetitions,
            nextReviewDate: card.nextReviewDate
        )
        let newState = SRSEngine.apply(rating, to: oldState)
        card.easeFactor = newState.easeFactor
        card.interval = newState.interval
        card.repetitions = newState.repetitions
        card.nextReviewDate = newState.nextReviewDate
        card.lastReviewedAt = .now

        // ReviewLog
        let log = ReviewLog(
            cardId: card.id,
            rating: rating.rawValue,
            previousInterval: oldState.interval,
            newInterval: newState.interval
        )
        modelContext.insert(log)
        try? modelContext.save()

        // Atualiza widget timeline com novo snapshot (palavra revisada vira "palavra do dia")
        publishWidgetSnapshot(reviewedJust: card)

        showAnswer = false
        index += 1
        reviewedCount += 1
    }

    private func publishWidgetSnapshot(reviewedJust justReviewed: VocabCard) {
        // Buscar usuário + todos os cards rapidamente. Como não temos @Query aqui
        // (recebemos `cards` como parâmetro), faz um fetch ad-hoc.
        let user = try? modelContext.fetch(FetchDescriptor<User>()).first
        let all = (try? modelContext.fetch(FetchDescriptor<VocabCard>())) ?? []
        let now = Date()
        let due = all.filter { $0.nextReviewDate <= now }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }

        let snapshot = WidgetSnapshot(
            streakDays: user?.streakDays ?? 0,
            xp: user?.xp ?? 0,
            dueCount: due.count,
            nextDueCard: due.first.map(SharedCard.from),
            wordOfDay: SharedCard.from(justReviewed)
        )
        WidgetDataPublisher.publish(snapshot: snapshot)
    }

    private func intervalLabel(for rating: Rating, card: VocabCard) -> String {
        let current = SRSState(
            easeFactor: card.easeFactor,
            interval: card.interval,
            repetitions: card.repetitions,
            nextReviewDate: card.nextReviewDate
        )
        let next = SRSEngine.apply(rating, to: current)
        if next.interval == 0 { return "<1d" }
        if next.interval < 30 { return "\(next.interval)d" }
        return "\(next.interval / 30)m"
    }

    private func color(for rating: Rating) -> Color {
        switch rating {
        case .again: return .red
        case .hard: return .orange
        case .good: return .blue
        case .easy: return .green
        }
    }

    private func genderColor(_ g: String) -> Color { Color.forGender(g) }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        utterance.rate = 0.45
        AVSpeechSynthesizer.shared.speak(utterance)
    }
}
