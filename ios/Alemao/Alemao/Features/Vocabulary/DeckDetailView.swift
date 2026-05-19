import SwiftData
import SwiftUI

struct DeckDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let deck: Deck
    @State private var showAddCard = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ReviewSessionView(cards: deck.cards)
                } label: {
                    Label("Revisar tudo (\(deck.cards.count))", systemImage: "rectangle.stack.fill")
                }
                .disabled(deck.cards.isEmpty)

                Button {
                    showAddCard = true
                } label: {
                    Label("Adicionar palavra", systemImage: "plus.circle")
                }
            }

            Section("Cards") {
                if deck.cards.isEmpty {
                    Text("Vazio").foregroundStyle(.secondary)
                } else {
                    ForEach(deck.cards.sorted(by: { $0.headword < $1.headword }), id: \.id) { card in
                        NavigationLink {
                            CardDetailView(card: card)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    if let g = card.gender {
                                        Text(g).foregroundStyle(genderColor(g)).bold()
                                    }
                                    Text(card.headword).bold()
                                    if card.isVerb {
                                        Image(systemName: "tablecells")
                                            .font(.caption2)
                                            .foregroundStyle(.purple)
                                    }
                                    Spacer()
                                    Text(formatInterval(card.interval))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                                Text(card.translation).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let sorted = deck.cards.sorted(by: { $0.headword < $1.headword })
                        for i in offsets { modelContext.delete(sorted[i]) }
                        try? modelContext.save()
                    }
                }
            }
        }
        .navigationTitle(deck.name)
        .sheet(isPresented: $showAddCard) {
            AddCardSheet(deck: deck)
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

    private func formatInterval(_ days: Int) -> String {
        if days == 0 { return "novo" }
        if days < 30 { return "\(days)d" }
        return "\(days / 30)m"
    }
}

private struct AddCardSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let deck: Deck
    @State private var word: String = ""
    @State private var translation: String = ""
    @State private var gender: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Palavra (alemão)", text: $word)
                TextField("Tradução", text: $translation)
                Picker("Gênero", selection: $gender) {
                    Text("—").tag("")
                    Text("der").tag("der")
                    Text("die").tag("die")
                    Text("das").tag("das")
                }
            }
            .navigationTitle("Adicionar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let card = VocabCard(
                            headword: word.trimmingCharacters(in: .whitespaces),
                            gender: gender.isEmpty ? nil : gender,
                            translation: translation,
                            deck: deck
                        )
                        modelContext.insert(card)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
