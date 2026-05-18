import SwiftData
import SwiftUI

/// Roda o teste de nivelamento: gera 12 questões, coleta respostas, estima CEFR.
struct PlacementTestRunner: View {
    @Environment(\.modelContext) private var modelContext
    let appleCredentials: AppleAuthService.Credentials
    @Binding var isPresented: Bool

    @State private var test: PlacementTester.Test?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var answers: [String: Int] = [:]
    @State private var currentIndex: Int = 0
    @State private var estimatedLevel: String?

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Gerando teste…").padding()
            } else if let test {
                if let estimatedLevel {
                    resultView(level: estimatedLevel, test: test)
                } else {
                    questionView(test)
                }
            } else if let errorMessage {
                ContentUnavailableView(
                    "Erro",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                Button("Tentar novamente") { Task { await generate() } }
                    .buttonStyle(.bordered)
            } else {
                ProgressView()
                    .task { await generate() }
            }
        }
    }

    @MainActor
    private func generate() async {
        isLoading = true
        errorMessage = nil
        do {
            test = try await PlacementTester().generate()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func questionView(_ test: PlacementTester.Test) -> some View {
        let q = test.questions[currentIndex]
        return VStack(alignment: .leading, spacing: 16) {
            ProgressView(value: Double(currentIndex), total: Double(test.questions.count))

            HStack {
                Text("Questão \(currentIndex + 1) / \(test.questions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(q.level_cefr)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(Capsule())
            }

            Text(q.prompt_pt).font(.callout).foregroundStyle(.secondary)
            Text(q.german_sentence)
                .font(.title3)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            ForEach(Array(q.options.enumerated()), id: \.offset) { idx, option in
                Button {
                    answers[q.id] = idx
                    advance(in: test)
                } label: {
                    HStack {
                        Text(option).font(.body)
                        Spacer()
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
        .padding(.top)
    }

    private func resultView(level: String, test: PlacementTester.Test) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("Seu nível estimado")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(level)
                .font(.system(size: 60, weight: .bold))
            Text(levelDescription(level))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                let user = User(
                    appleUserIdentifier: appleCredentials.userIdentifier,
                    email: appleCredentials.email,
                    displayName: appleCredentials.displayName,
                    levelCEFR: level,
                    nativeLanguage: "pt"
                )
                modelContext.insert(user)
                try? modelContext.save()
                isPresented = false
            } label: {
                Text("Começar").frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding()
    }

    private func advance(in test: PlacementTester.Test) {
        if currentIndex + 1 < test.questions.count {
            currentIndex += 1
        } else {
            estimatedLevel = PlacementTester.estimateLevel(test: test, answers: answers)
        }
    }

    private func levelDescription(_ level: String) -> String {
        switch level {
        case "A1": return "Iniciante — começa do absoluto zero ou recém-aprendeu o básico."
        case "A2": return "Básico — dá conta de situações cotidianas simples."
        case "B1": return "Intermediário — pode viajar, contar histórias, expressar opiniões."
        case "B2": return "Intermediário avançado — conversação fluente sobre tópicos diversos."
        case "C1": return "Avançado — entende textos complexos e usa a língua de modo flexível."
        case "C2": return "Proficiente — perto do nível nativo."
        default: return ""
        }
    }
}
