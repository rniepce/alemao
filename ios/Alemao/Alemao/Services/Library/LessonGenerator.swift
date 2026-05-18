import Foundation

/// Orquestra geração de conteúdo via RAG + Gemini.
///
/// Duas APIs principais:
/// - `generateLesson(topic:level:)` — produz uma `GeneratedLesson` estruturada.
/// - `askTutor(question:level:)` — resposta livre em Markdown com citações.
///
/// Ambos usam o `Retriever` para encontrar trechos relevantes nos livros
/// bundleados e injetam esse contexto no prompt para o LLM.
final class LessonGenerator {
    let retriever: Retriever
    let llmClient: LLMClient

    init(retriever: Retriever, llmClient: LLMClient) {
        self.retriever = retriever
        self.llmClient = llmClient
    }

    // MARK: - Estruturas decodáveis (espelham seed_lessons.py)

    struct GeneratedContent: Decodable {
        let title: String
        let summary: String
        let explanation_md: String
        let examples: [LessonExample]
        let exercises: [LessonExercise]
        let citations: [LessonCitation]
    }

    struct LessonExample: Codable {
        let de: String
        let pt: String
        let note: String?
    }

    struct LessonExercise: Codable {
        let question: String
        let answer: String
        let explanation: String?
    }

    struct LessonCitation: Codable {
        let book_id: String
        let book_title: String
        let section_title: String?
        let page_start: Int
        let page_end: Int
        let excerpt: String
    }

    struct TutorAnswer: Decodable {
        let answer_md: String
        let citations: [LessonCitation]
    }

    // MARK: - Lesson on demand

    func generateLesson(
        topic: String,
        level: String = "B1",
        retrievalLimit: Int = 8
    ) async throws -> GeneratedContent {
        let hits = try await retriever.retrieve(query: topic, limit: retrievalLimit)
        let context = Self.formatContext(hits)

        let system = """
        Você é um professor experiente de alemão para falantes de português, que prepara
        lições didáticas claras e bem fundamentadas.

        Você receberá um tópico, um nível CEFR alvo, e trechos relevantes de livros de
        gramática (em inglês ou alemão). Sua tarefa é gerar uma LIÇÃO em português
        brasileiro estruturada conforme o JSON abaixo:

        {
          "title": "Título em português",
          "summary": "1-2 frases de resumo",
          "explanation_md": "Explicação didática completa em Markdown (use ## headings, listas, tabelas)",
          "examples": [{"de": "...", "pt": "...", "note": null}],
          "exercises": [{"question": "...", "answer": "...", "explanation": null}],
          "citations": [{"book_id": "...", "book_title": "...", "section_title": "...", "page_start": N, "page_end": N, "excerpt": "..."}]
        }

        Importantíssimo:
        - A explicação é SUA (transformativa) inspirada nos trechos, NÃO copie blocos.
        - Inclua 5-10 exemplos e 3-5 exercícios com gabarito.
        - Adapte profundidade ao nível CEFR.
        - Nas citações, preserve EXATAMENTE os valores de book_id, book_title, page_start, page_end
          conforme vieram nos trechos fornecidos.
        - Retorne APENAS o JSON, sem texto antes ou depois.
        """

        let prompt = """
        Tópico: \(topic)
        Nível CEFR alvo: \(level)

        Trechos da biblioteca:

        \(context)

        Gere a lição em JSON.
        """

        return try await llmClient.generateStructured(
            prompt: prompt,
            systemInstruction: system,
            responseType: GeneratedContent.self,
            responseJSONSchema: nil,
            temperature: 0.4
        )
    }

    // MARK: - Pergunte ao tutor

    func askTutor(
        question: String,
        level: String? = nil,
        retrievalLimit: Int = 6
    ) async throws -> TutorAnswer {
        let hits = try await retriever.retrieve(query: question, limit: retrievalLimit)
        let context = Self.formatContext(hits)

        let system = """
        Você é um tutor experiente de alemão para falantes de português brasileiro.
        Responda à pergunta do aluno usando como base os trechos dos livros fornecidos.

        Retorne APENAS um JSON com este formato:
        {
          "answer_md": "Resposta em português, em Markdown. Use ## headings, listas e tabelas quando ajudar.",
          "citations": [{"book_id": "...", "book_title": "...", "section_title": "...", "page_start": N, "page_end": N, "excerpt": "..."}]
        }

        Regras:
        - Responda em português brasileiro, didático mas direto.
        - SEMPRE cite as fontes — só inclua trechos que apareceram nos contextos fornecidos.
        - Preserve EXATAMENTE os valores de book_id, book_title, page_start, page_end das citações.
        - Se nenhum trecho ajudar a responder, diga isso na answer_md e retorne citations vazia.
        - Não invente regras gramaticais que não estejam apoiadas pelos trechos ou pelo seu conhecimento sólido.
        """

        let levelHint = level.map { "Nível do aluno: \($0)\n" } ?? ""
        let prompt = """
        \(levelHint)Pergunta do aluno: \(question)

        Trechos da biblioteca:

        \(context)
        """

        return try await llmClient.generateStructured(
            prompt: prompt,
            systemInstruction: system,
            responseType: TutorAnswer.self,
            responseJSONSchema: nil,
            temperature: 0.3
        )
    }

    // MARK: - Helpers

    private static func formatContext(_ hits: [Retriever.Hit]) -> String {
        if hits.isEmpty { return "(nenhum trecho relevante encontrado nos livros)" }
        return hits.enumerated().map { idx, h in
            """
            [Trecho \(idx + 1)] book_id=\(h.bookId) | livro="\(h.bookTitle)" | seção="\(h.sectionTitle ?? "—")" | páginas \(h.pageStart)-\(h.pageEnd)

            \(h.text)
            --- fim do trecho \(idx + 1) ---
            """
        }.joined(separator: "\n\n")
    }

    // MARK: - JSON helpers para conversão GeneratedContent ↔ GeneratedLesson

    static func encodeJSON<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }
}
