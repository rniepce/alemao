import Foundation

/// Gera textos de leitura sob demanda usando RAG + Gemini.
/// O texto é adaptado a um nível CEFR e tema escolhidos.
final class ReadingGenerator {
    let retriever: Retriever?
    let llmClient: LLMClient

    init(retriever: Retriever? = nil, llmClient: LLMClient = GeminiClient()) {
        self.retriever = retriever
        self.llmClient = llmClient
    }

    struct GeneratedReading: Decodable {
        let title: String
        let level_cefr: String
        let body_de: String
        let glossary: [GlossaryItem]
        let comprehension_questions: [ComprehensionQuestion]

        struct GlossaryItem: Codable {
            let de: String
            let pt: String
        }
        struct ComprehensionQuestion: Codable {
            let question: String
            let answer: String
        }
    }

    func generate(
        topic: String,
        levelCEFR: String = "B1",
        wordCount: Int = 200
    ) async throws -> GeneratedReading {
        // Retrieval opcional — busca trechos do tópico nos livros para estilo
        var context = ""
        if let retriever {
            let hits = (try? await retriever.retrieve(query: topic, limit: 3)) ?? []
            if !hits.isEmpty {
                context = "Contexto da biblioteca (use como inspiração de vocabulário e estilo):\n\n"
                    + hits.enumerated().map { idx, h in
                        "[\(idx + 1)] \(h.bookTitle) — \(h.text.prefix(400))…"
                    }.joined(separator: "\n\n")
            }
        }

        let system = """
        Você é um autor de textos didáticos em alemão. Produza um texto de leitura
        adequado ao nível CEFR pedido, sobre o tópico solicitado. Retorne APENAS
        um JSON com este formato:

        {
          "title": "Título em alemão",
          "level_cefr": "A1/A2/B1/B2/C1/C2",
          "body_de": "Texto principal em alemão, em parágrafos. ~XXX palavras.",
          "glossary": [{"de": "palavra ou expressão", "pt": "tradução"}],
          "comprehension_questions": [{"question": "...", "answer": "..."}]
        }

        Regras:
        - body_de em alemão claro e adequado ao nível (vocabulário, sintaxe).
        - Glossary com 5-10 palavras-chave que um aluno do nível possa não saber.
        - 3-5 perguntas de compreensão em alemão (com resposta em alemão também).
        - Não inclua tradução do texto inteiro — só do glossário.
        """

        let userPrompt = """
        Tópico: \(topic)
        Nível: \(levelCEFR)
        Tamanho-alvo: ~\(wordCount) palavras
        \(context.isEmpty ? "" : "\n" + context)
        """

        return try await llmClient.generateStructured(
            prompt: userPrompt,
            systemInstruction: system,
            responseType: GeneratedReading.self,
            responseJSONSchema: nil,
            temperature: 0.6
        )
    }
}
