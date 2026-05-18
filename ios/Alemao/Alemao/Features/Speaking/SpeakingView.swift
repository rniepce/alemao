import SwiftData
import SwiftUI

/// Aba Fala: lista de cenários de role-play. Tocar inicia conversa com Live API.
struct SpeakingView: View {
    @Query(sort: \ConversationSession.startedAt, order: .reverse)
    private var sessions: [ConversationSession]

    var body: some View {
        NavigationStack {
            List {
                Section("Cenários") {
                    ForEach(Scenario.all, id: \.id) { scenario in
                        NavigationLink {
                            ConversationView(scenario: scenario)
                        } label: {
                            ScenarioRow(scenario: scenario)
                        }
                    }
                }

                if !sessions.isEmpty {
                    Section("Conversas salvas") {
                        ForEach(sessions, id: \.id) { s in
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(s.scenarioTitle).font(.subheadline.bold())
                                    Spacer()
                                    Text(s.startedAt, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                if let cefr = s.levelCEFR {
                                    Text(cefr).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Fala")
        }
    }
}

private struct ScenarioRow: View {
    let scenario: Scenario
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(scenario.title).font(.headline)
                Spacer()
                Text(scenario.level)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(Capsule())
            }
            Text(scenario.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

/// Catálogo de cenários estáticos. Pode evoluir para algo gerado por LLM no futuro.
struct Scenario: Identifiable {
    let id: String
    let title: String
    let level: String
    let description: String
    let systemPrompt: String

    static let all: [Scenario] = [
        Scenario(
            id: "cafe_berlin", title: "Café em Berlim", level: "A1",
            description: "Pedindo um café e um Brötchen no balcão.",
            systemPrompt: """
            Você é o(a) atendente de um café tradicional em Berlim. Fale em alemão simples (nível A1),
            seja amável e paciente. Inicie cumprimentando o cliente e pergunte o que ele(a) quer.
            Se o aluno cometer erros, corrija sutilmente em uma frase paralela em alemão,
            mas continue a conversa. Use frases curtas. NÃO mude para inglês ou português.
            """
        ),
        Scenario(
            id: "bahnhof", title: "Comprando passagem", level: "A2",
            description: "Bilheteria de trem — você precisa ir de Munique a Frankfurt.",
            systemPrompt: """
            Você é o(a) vendedor(a) de passagens da DB (Deutsche Bahn) num balcão de estação.
            Fale em alemão de nível A2. O aluno precisa comprar um bilhete de Munique a Frankfurt.
            Pergunte horários, classe, ida ou ida-e-volta, número de passageiros. Use frases curtas
            e claras. Se o aluno cometer erros, corrija sutilmente. NÃO mude para inglês ou português.
            """
        ),
        Scenario(
            id: "vorstellung", title: "Apresentação pessoal", level: "A2",
            description: "Conversa casual: apresentações, hobbies, profissão.",
            systemPrompt: """
            Você é um(a) novo(a) colega de trabalho que conheceu o(a) aluno(a) num evento.
            Fale em alemão A2. Faça perguntas naturais sobre nome, idade, profissão, hobbies,
            de onde é, há quanto tempo está na Alemanha. Use uma frase por turno. Se errar, corrija
            sutilmente em alemão. NÃO mude para inglês ou português.
            """
        ),
        Scenario(
            id: "vorstellungsgespraech", title: "Entrevista de emprego", level: "B2",
            description: "Entrevista para vaga de desenvolvedor numa Hochtechnologiefirma.",
            systemPrompt: """
            Você é o(a) gerente de RH de uma empresa de tecnologia em Hamburgo. Conduza uma
            entrevista em alemão B2. Pergunte sobre experiência, motivação, projetos, qual seu maior
            desafio. Use registro semi-formal (Sie). Dê feedback construtivo após cada resposta.
            Se o aluno cometer erros graves, corrija em alemão. NÃO mude para inglês ou português.
            """
        ),
        Scenario(
            id: "diskussion_klima", title: "Discussão: clima", level: "C1",
            description: "Debate sobre políticas climáticas e responsabilidade individual.",
            systemPrompt: """
            Você é um(a) jornalista alemão(ã) entrevistando o(a) aluno(a) sobre suas opiniões
            quanto a mudanças climáticas. Fale em alemão C1, com sintaxe avançada e vocabulário
            específico. Provoque o aluno com contra-argumentos. Corrija erros sutilmente quando
            apropriado, sem interromper o fluxo. NÃO mude para inglês ou português.
            """
        ),
    ]
}

#Preview {
    SpeakingView()
        .modelContainer(for: [ConversationSession.self], inMemory: true)
}
