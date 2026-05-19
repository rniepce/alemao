import SwiftData
import SwiftUI

/// Quiz interativo de conjugação de verbos.
///
/// Pega verbos do SwiftData (com `pos == "verb"` e `conjugationJSON` válido),
/// sorteia um verbo + tempo + pessoa, e desafia o usuário a digitar a forma.
struct ConjugationQuizView: View {
    @Query private var allCards: [VocabCard]
    @State private var question: Question?
    @State private var answer: String = ""
    @State private var result: Result?
    @State private var correctCount: Int = 0
    @State private var totalCount: Int = 0
    @State private var enabledTenses: Set<VerbConjugation.Tense> = Set(VerbConjugation.Tense.allCases)
    @State private var showSettings: Bool = false
    @FocusState private var inputFocused: Bool

    struct Question {
        let verb: String                      // infinitivo
        let translationPT: String
        let tense: VerbConjugation.Tense
        let person: VerbConjugation.Person
        let expected: String                  // forma correta esperada
        let isSeparable: Bool
        let isReflexive: Bool
    }

    enum Result { case correct, almost(String), incorrect(String) }

    private var verbCards: [VocabCard] {
        allCards.filter { $0.isVerb }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if verbCards.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        questionCard
                        if let result {
                            resultCard(result)
                        }
                    }
                    .padding()
                }
                Divider()
                inputBar
            }
        }
        .navigationTitle("Quiz de conjugação")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .task { ensureQuestion() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            statBubble(value: "\(correctCount)", label: "acertos", color: .green)
            statBubble(value: "\(totalCount - correctCount)", label: "erros", color: .red)
            statBubble(
                value: totalCount > 0 ? "\(correctCount * 100 / totalCount)%" : "—",
                label: "taxa", color: .blue
            )
            statBubble(value: "\(totalCount)", label: "total", color: .secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var empty: some View {
        ContentUnavailableView(
            "Sem verbos para revisar",
            systemImage: "books.vertical",
            description: Text(
                "Abra a aba Vocabulário primeiro para o app carregar o deck de verbos."
            )
        )
    }

    @ViewBuilder
    private var questionCard: some View {
        if let q = question {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(q.tense.label)
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(tenseColor(q.tense).opacity(0.2))
                        .foregroundStyle(tenseColor(q.tense))
                        .clipShape(Capsule())
                    if q.isSeparable {
                        Text("separável")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    if q.isReflexive {
                        Text("reflexivo")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.pink.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    Spacer()
                }

                Text("Conjugue")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(q.verb)
                        .font(.title.bold())
                    Text(q.translationPT)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Text("para")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(q.person.label)
                        .font(.title3.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private func resultCard(_ result: Result) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch result {
            case .correct:
                Label("Correto!", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            case .almost(let expected):
                Label("Quase — atenção ao acento/ortografia", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Esperado: ").font(.caption).foregroundStyle(.secondary)
                    + Text(expected).font(.callout.bold())
            case .incorrect(let expected):
                Label("Errou", systemImage: "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text("Resposta correta: ").font(.caption).foregroundStyle(.secondary)
                    + Text(expected).font(.callout.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(resultBackground(result))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func resultBackground(_ r: Result) -> Color {
        switch r {
        case .correct: return .green.opacity(0.12)
        case .almost: return .orange.opacity(0.12)
        case .incorrect: return .red.opacity(0.12)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Digite a forma…", text: $answer)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($inputFocused)
                .submitLabel(.go)
                .onSubmit { commit() }

            if result == nil {
                Button("Verificar", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                Button("Próximo", action: next)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Tempos a praticar") {
                    ForEach(VerbConjugation.Tense.allCases) { tense in
                        Toggle(tense.label, isOn: Binding(
                            get: { enabledTenses.contains(tense) },
                            set: { isOn in
                                if isOn { enabledTenses.insert(tense) }
                                else { enabledTenses.remove(tense) }
                                if enabledTenses.isEmpty { enabledTenses = [.praesens] }
                            }
                        ))
                    }
                }
                Section {
                    Button("Reiniciar contagem") {
                        correctCount = 0
                        totalCount = 0
                    }
                }
            }
            .navigationTitle("Ajustes do quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pronto") { showSettings = false }
                }
            }
        }
    }

    // MARK: - Logic

    private func ensureQuestion() {
        if question == nil { next() }
    }

    private func next() {
        result = nil
        answer = ""
        question = randomQuestion()
        inputFocused = true
    }

    private func randomQuestion() -> Question? {
        guard let card = verbCards.randomElement(),
              let conj = VerbConjugation.decode(from: card.conjugationJSON)
        else { return nil }

        let tense = enabledTenses.randomElement() ?? .praesens
        let person = VerbConjugation.Person.allCases.randomElement() ?? .ich
        let expected = conj.forms(for: tense).form(for: person)

        return Question(
            verb: conj.infinitive,
            translationPT: conj.translation_pt,
            tense: tense,
            person: person,
            expected: expected,
            isSeparable: conj.is_separable,
            isReflexive: conj.is_reflexive
        )
    }

    private func commit() {
        guard let q = question, result == nil else { return }
        let userTrim = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let expectedTrim = q.expected.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let userFolded = userTrim.folding(options: .diacriticInsensitive, locale: .current)
        let expectedFolded = expectedTrim.folding(options: .diacriticInsensitive, locale: .current)

        totalCount += 1
        if userTrim == expectedTrim {
            result = .correct
            correctCount += 1
        } else if userFolded == expectedFolded {
            // Acertou mas errou diacrítico (ä/ö/ü/ß)
            result = .almost(q.expected)
            correctCount += 1   // conta como acerto parcial
        } else {
            result = .incorrect(q.expected)
        }
        inputFocused = false
    }

    // MARK: - Helpers

    private func statBubble(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tenseColor(_ t: VerbConjugation.Tense) -> Color {
        switch t {
        case .praesens: return .blue
        case .praeteritum: return .orange
        case .konjunktivII: return .purple
        }
    }
}

extension ConjugationQuizView.Result: Equatable {
    static func == (lhs: ConjugationQuizView.Result, rhs: ConjugationQuizView.Result) -> Bool {
        switch (lhs, rhs) {
        case (.correct, .correct): return true
        case let (.almost(a), .almost(b)): return a == b
        case let (.incorrect(a), .incorrect(b)): return a == b
        default: return false
        }
    }
}
