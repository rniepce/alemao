import Foundation

/// Gera um teste de nivelamento CEFR via LLM, baseado em conhecimento gramatical.
///
/// As perguntas são geradas dinamicamente (não bundleadas) pois o LLM pode
/// adaptar dificuldade. Retorna 12 perguntas cobrindo A1-C1.
final class PlacementTester {
    let llmClient: LLMClient

    init(llmClient: LLMClient = GeminiClient()) {
        self.llmClient = llmClient
    }

    struct Test: Decodable {
        let questions: [Question]

        struct Question: Codable, Hashable {
            let id: String
            let level_cefr: String           // A1...C1
            let prompt_pt: String            // enunciado em português
            let german_sentence: String      // frase em alemão com lacuna marcada como ___
            let options: [String]            // 4 opções
            let correct_index: Int           // 0-3
            let explanation_pt: String       // explicação curta
        }
    }

    /// Estima CEFR a partir das respostas.
    /// Heurística: a partir do nível mais alto em que ainda acertou ≥2/3 das questões.
    static func estimateLevel(test: Test, answers: [String: Int]) -> String {
        let levels: [String] = ["A1", "A2", "B1", "B2", "C1"]
        var byLevel: [String: (correct: Int, total: Int)] = [:]
        for q in test.questions {
            let stat = byLevel[q.level_cefr] ?? (0, 0)
            let userAns = answers[q.id]
            let correct = userAns == q.correct_index
            byLevel[q.level_cefr] = (
                correct: stat.correct + (correct ? 1 : 0),
                total: stat.total + 1
            )
        }
        var best = "A1"
        for level in levels {
            guard let stat = byLevel[level], stat.total > 0 else { continue }
            let ratio = Double(stat.correct) / Double(stat.total)
            if ratio >= 0.66 { best = level }
        }
        return best
    }

    func generate() async throws -> Test {
        let system = """
        Você é um avaliador de proficiência em alemão para falantes de português brasileiro.
        Gere um teste de nivelamento com EXATAMENTE 12 questões de múltipla escolha (4 opções),
        cobrindo os níveis CEFR: 2 questões A1, 2 A2, 3 B1, 3 B2, 2 C1.

        Cada questão é uma frase em alemão com UMA lacuna (marcada como ___) que o aluno
        deve preencher. Foque em:
        - declinação (artigos, adjetivos, pronomes)
        - conjugação de verbos (incluindo Konjunktiv II em B2+)
        - preposições e seus casos
        - ordem de palavras
        - tempos verbais (Präteritum, Perfekt, Futur)
        - conectivos (weil, obwohl, trotzdem, deshalb...)

        Retorne APENAS JSON neste formato:

        {
          "questions": [
            {
              "id": "q1",
              "level_cefr": "A1|A2|B1|B2|C1",
              "prompt_pt": "Enunciado em português (ex: \\"Complete a frase\\")",
              "german_sentence": "Ich ___ ein Buch.",
              "options": ["lese", "lest", "liest", "lesen"],
              "correct_index": 0,
              "explanation_pt": "Para 'ich' (1ª pessoa singular), o verbo lesen é 'lese'."
            }
          ]
        }

        Regras:
        - Use ids "q1", "q2", ..., "q12".
        - Apenas UMA opção correta por questão.
        - Lacuna marcada como exatamente 3 underscores: ___
        """

        return try await llmClient.generateStructured(
            prompt: "Gere o teste agora.",
            systemInstruction: system,
            responseType: Test.self,
            responseJSONSchema: nil,
            temperature: 0.5
        )
    }
}
