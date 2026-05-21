import SwiftData
import SwiftUI

/// Aba Fala: lista de cenários de role-play. Tocar inicia conversa com Live API.
struct SpeakingView: View {
    @Query(sort: \ConversationSession.startedAt, order: .reverse)
    private var sessions: [ConversationSession]

    @State private var showFreeChatPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showFreeChatPicker = true
                    } label: {
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                                .font(.title)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Conversa livre")
                                    .font(.headline)
                                Text("Bate-papo aberto em alemão com legendas em tempo real")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, AppSpacing.xs)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Treinar conversação")
                }

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
            .sheet(isPresented: $showFreeChatPicker) {
                FreeChatPickerSheet()
            }
        }
    }
}

/// Picker para iniciar conversa livre: escolhe nível CEFR e abre ConversationView
/// com um scenario gerado dinamicamente (prompt de tutor amigável).
private struct FreeChatPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var level: String = "B1"
    @State private var startedScenario: Scenario?

    private let levels = ["A1", "A2", "B1", "B2", "C1"]
    private let descriptions: [String: String] = [
        "A1": "Iniciante: frases simples, vocabulário básico, presente do indicativo.",
        "A2": "Básico: passado simples, vocabulário cotidiano, perguntas comuns.",
        "B1": "Intermediário: opinião, narrar histórias, situações imprevistas.",
        "B2": "Intermediário avançado: discussões, argumentos, vocabulário amplo.",
        "C1": "Avançado: temas abstratos, registro formal, idiomáticas.",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Seu nível atual") {
                    Picker("Nível CEFR", selection: $level) {
                        ForEach(levels, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(descriptions[level] ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    NavigationLink {
                        ConversationView(scenario: Scenario.freeChat(level: level))
                    } label: {
                        Label("Começar conversa", systemImage: "play.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                } footer: {
                    Text(
                        "O tutor começará com um cumprimento e pergunta aberta. " +
                        "Conversem sobre qualquer assunto — clima, hobbies, planos, trabalho, viagens. " +
                        "Ele vai corrigir erros sutilmente (recasting) sem interromper o fluxo, " +
                        "manter as falas curtas para você ter espaço de praticar, " +
                        "e ajustar a complexidade ao seu nível."
                    )
                    .font(.caption2)
                }
            }
            .navigationTitle("Conversa livre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
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

    /// Conversa livre: gera um Scenario customizado a partir do nível CEFR.
    /// O prompt configura o LLM como tutor amigável que corrige sutilmente,
    /// faz recasting, mantém turnos curtos e ajusta vocabulário ao nível.
    static func freeChat(level: String) -> Scenario {
        Scenario(
            id: "free_chat_\(level)",
            title: "Conversa livre (\(level))",
            level: level,
            description: "Bate-papo aberto — tutor amigável, correção sutil, qualquer tópico.",
            systemPrompt: freeChatSystemPrompt(level: level)
        )
    }

    private static func freeChatSystemPrompt(level: String) -> String {
        let levelGuide: String
        switch level {
        case "A1":
            levelGuide = "Use frases muito simples (5-8 palavras). Apenas presente. Vocabulário básico (família, comida, dia a dia). Repita estruturas para fixação."
        case "A2":
            levelGuide = "Frases curtas. Use passado (Perfekt), futuro com werden, modais. Vocabulário cotidiano. Frases conectadas com 'und', 'aber', 'weil'."
        case "B1":
            levelGuide = "Vocabulário variado. Use Konjunktiv II ocasionalmente, Präteritum em narrativas. Conectores: deshalb, trotzdem, obwohl. Permita nuances."
        case "B2":
            levelGuide = "Vocabulário amplo, inclusive idiomático. Konjunktiv I/II naturais. Subordinadas complexas. Discuta temas abstratos. Recapitule com 'Also, du meinst...'"
        case "C1":
            levelGuide = "Registro variado (informal/formal). Vocabulário rico, expressões idiomáticas, registros literários. Discuta política, filosofia, arte. Provoque pensamento."
        default:
            levelGuide = "Adapte naturalmente ao nível do aluno conforme a conversa."
        }

        return """
        Du bist ein freundlicher und geduldiger Deutschlehrer im Gespräch mit einem brasilianischen Schüler.

        REGRAS ABSOLUTAS:
        1. Fale SEMPRE e APENAS em alemão. Nunca traduza para português ou inglês, mesmo se o aluno pedir.
        2. Se o aluno disser algo em português, responda em alemão simples reformulando o que ele disse: "Ah, du meinst... [versão em alemão]?"
        3. Se o aluno não entender, parafraseie com palavras mais simples — NÃO mude de idioma.

        ESTILO:
        - Comece a conversa com uma saudação amigável + uma pergunta aberta sobre como ele está/o que está fazendo.
        - Mantenha turnos CURTOS (1-3 frases). O aluno precisa ter espaço para falar.
        - Faça perguntas para manter o fluxo: "Was machst du sonst gern?", "Wie war's gestern?", "Was denkst du darüber?"
        - Se o aluno fica em silêncio ou trava, sugira um tópico novo (clima, hobbies, planos, filmes, comida, viagens, trabalho).
        - Use natural, expressões idiomáticas comuns, mas evite gírias ou jargões obscuros.

        CORREÇÃO PEDAGÓGICA:
        - Quando o aluno comete um erro, NÃO o corrija explicitamente nem o interrompa.
        - Em vez disso, faça "recasting": reformule a frase corretamente como parte natural de sua resposta.
          Exemplo: aluno diz "Ich bin müde gewesen gestern" → você responde: "Ah, du WARST gestern müde. Hast du gut geschlafen?"
        - Elogie progressos sutilmente: "Genau!", "Gut gesagt!", "Sehr schön!".
        - Se o aluno usa uma palavra nova ou complexa corretamente, mostre que notou: "Ich sehe, du kennst das Wort '...' — super!"

        NÍVEL DO ALUNO: \(level).
        \(levelGuide)

        NUNCA quebre a quarta parede mencionando que você é IA, modelo, prompt, instrução etc. Você é simplesmente um(a) amigo(a) alemão(ã) conversando.
        """
    }

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
