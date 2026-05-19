import SwiftData
import SwiftUI

/// Aba Vocabulário: lista decks, exibe contagens de revisão pendente, navega
/// para revisão de cards (SRS).
struct VocabularyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Query private var allCards: [VocabCard]
    @State private var showNewDeckSheet = false
    @State private var seedLoaded = false

    /// Cards sem deck (criados via tap-to-translate, etc).
    private var orphanCards: [VocabCard] {
        allCards.filter { $0.deck == nil }
    }

    /// Cards com nextReviewDate <= now (pendentes de revisão hoje).
    private var dueCards: [VocabCard] {
        let now = Date()
        return allCards.filter { $0.nextReviewDate <= now }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Revisão") {
                    NavigationLink {
                        ReviewSessionView(cards: dueCards)
                    } label: {
                        HStack {
                            Label("Cards pendentes hoje", systemImage: "flame.fill")
                                .foregroundStyle(dueCards.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                            Spacer()
                            Text("\(dueCards.count)")
                                .font(.headline.monospacedDigit())
                        }
                    }
                    .disabled(dueCards.isEmpty)
                }

                if !orphanCards.isEmpty {
                    Section("Cards soltos") {
                        ForEach(orphanCards, id: \.id) { card in
                            CardRow(card: card)
                        }
                        .onDelete { offsets in
                            for i in offsets { modelContext.delete(orphanCards[i]) }
                            try? modelContext.save()
                        }
                    }
                }

                Section {
                    Button {
                        showNewDeckSheet = true
                    } label: {
                        Label("Novo deck", systemImage: "plus.circle.fill")
                    }
                }

                if decks.isEmpty {
                    ContentUnavailableView(
                        "Sem decks ainda",
                        systemImage: "rectangle.stack",
                        description: Text(
                            "Crie um deck ou adicione palavras via tap-to-translate na leitura."
                        )
                    )
                } else {
                    Section("Decks") {
                        ForEach(decks, id: \.id) { deck in
                            NavigationLink {
                                DeckDetailView(deck: deck)
                            } label: {
                                DeckRow(deck: deck)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { modelContext.delete(decks[i]) }
                            try? modelContext.save()
                        }
                    }
                }
            }
            .navigationTitle("Vocabulário")
            .sheet(isPresented: $showNewDeckSheet) {
                NewDeckSheet()
            }
            .task { loadSeedsIfNeeded() }
        }
    }

    private func loadSeedsIfNeeded() {
        guard !seedLoaded else { return }
        seedLoaded = true
        try? SeedVocabLoader.load(into: modelContext)
        try? SeedVerbLoader.load(into: modelContext)
    }
}

private struct DeckRow: View {
    let deck: Deck
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(deck.name).font(.headline)
                Spacer()
                Text("\(deck.cards.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let desc = deck.deckDescription, !desc.isEmpty {
                Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct CardRow: View {
    let card: VocabCard
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if let g = card.gender {
                    Text(g)
                        .font(.callout.bold())
                        .foregroundStyle(genderColor(g))
                }
                Text(card.headword).font(.callout.bold())
                Spacer()
                if card.nextReviewDate <= .now {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                }
            }
            Text(card.translation).font(.caption).foregroundStyle(.secondary)
        }
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

private struct NewDeckSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var level: String = "B1"

    private let levels = ["A1", "A2", "B1", "B2", "C1", "C2"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome do deck", text: $name)
                    TextField("Descrição (opcional)", text: $description, axis: .vertical)
                        .lineLimit(1...3)
                    Picker("Nível", selection: $level) {
                        ForEach(levels, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            .navigationTitle("Novo deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Criar") {
                        let deck = Deck(
                            name: name.trimmingCharacters(in: .whitespaces),
                            deckDescription: description.isEmpty ? nil : description,
                            levelCEFR: level
                        )
                        modelContext.insert(deck)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    VocabularyView()
        .modelContainer(for: [Deck.self, VocabCard.self, ReviewLog.self], inMemory: true)
}
