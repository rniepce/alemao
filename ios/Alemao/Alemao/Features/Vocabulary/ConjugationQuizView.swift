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
        HStack(spacing: AppSpacing.sm) {
            StatBubble(value: "\(correctCount)", label: "acertos", tint: .success)
            StatBubble(value: "\(totalCount - correctCount)", label: "erros", tint: .danger)
            StatBubble(
                value: totalCount > 0 ? "\(correctCount * 100 / totalCount)%" : "—",
                label: "taxa", tint: .info
            )
            StatBubble(value: "\(totalCount)", label: "total")
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
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    LevelBadge(q.tense.label, tint: tenseColor(q.tense))
                    if q.isSeparable {
                        LevelBadge("separável", tint: .tagSeparable, size: .small)
                    }
                    if q.isReflexive {
                        LevelBadge("reflexivo", tint: .tagReflexive, size: .small)
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

                if let hint = formatHint(for: q) {
                    Label(hint, systemImage: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
        }
    }

    /// Hint de formato quando o verbo tem partícula separável ou pronome reflexivo.
    /// Sem hint, usuário não sabe se digita "stehe" ou "stehe auf".
    private func formatHint(for q: Question) -> String? {
        if q.isSeparable {
            // Tenta extrair a partícula do final da forma esperada
            let parts = q.expected.split(separator: " ")
            if parts.count >= 2, let last = parts.last {
                return "Digite a forma completa, incluindo a partícula '\(last)' no fim"
            }
            return "Digite a forma completa (com partícula separada)"
        }
        if q.isReflexive {
            return "Inclua o pronome reflexivo correspondente à pessoa"
        }
        return nil
    }

    @ViewBuilder
    private func resultCard(_ result: Result) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch result {
            case .correct:
                Label("Correto!", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Color.success)
            case .almost(let expected):
                Label("Quase — atenção ao acento/ortografia", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.warning)
                Text("Esperado: ").font(.caption).foregroundStyle(.secondary)
                    + Text(expected).font(.callout.bold())
            case .incorrect(let expected):
                Label("Errou", systemImage: "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(Color.danger)
                Text("Resposta correta: ").font(.caption).foregroundStyle(.secondary)
                    + Text(expected).font(.callout.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .background(resultBackground(result))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private func resultBackground(_ r: Result) -> Color {
        switch r {
        case .correct: return Color.success.opacity(AppOpacity.medium)
        case .almost: return Color.warning.opacity(AppOpacity.medium)
        case .incorrect: return Color.danger.opacity(AppOpacity.medium)
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
        } else if isPartialMatch(user: userFolded, expected: expectedFolded) {
            // Para separáveis ("stehe" sem "auf") ou reflexivos ("freue" sem "mich")
            result = .almost(q.expected)
            correctCount += 1
        } else {
            result = .incorrect(q.expected)
        }
        inputFocused = false
    }

    /// Detecta resposta parcialmente correta: usuário digitou só a forma conjugada
    /// sem a partícula separável ou sem o pronome reflexivo.
    /// Ex: expected="stehe auf", user="stehe" → true.
    /// Ex: expected="freue mich", user="freue" → true.
    private func isPartialMatch(user: String, expected: String) -> Bool {
        let parts = expected.split(separator: " ")
        guard parts.count >= 2 else { return false }
        // Tenta cada subconjunto contíguo começando do início
        let firstPart = String(parts[0])
        return user == firstPart
    }

    // MARK: - Helpers

    private func tenseColor(_ t: VerbConjugation.Tense) -> Color {
        switch t {
        case .praesens: return .tensePraesens
        case .praeteritum: return .tensePraeteritum
        case .konjunktivII: return .tenseKonjunktivII
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
