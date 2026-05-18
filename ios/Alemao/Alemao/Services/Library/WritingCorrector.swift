import Foundation

/// Corretor de escrita em alemão. Retorna estrutura com erros categorizados
/// (gramática/vocabulário/registro/ortografia) e versão "como um nativo escreveria".
///
/// Usa retrieval para encontrar regras gramaticais relevantes nos livros, que
/// alimentam citações na correção (quando aplicável).
final class WritingCorrector {
    let retriever: Retriever?
    let llmClient: LLMClient

    init(retriever: Retriever? = nil, llmClient: LLMClient = GeminiClient()) {
        self.retriever = retriever
        self.llmClient = llmClient
    }

    enum ErrorCategory: String, Codable, CaseIterable {
        case grammar
        case vocabulary
        case spelling
        case register     // formalidade
        case wordOrder    // ordem das palavras
        case style

        var label: String {
            switch self {
            case .grammar: return "Gramática"
            case .vocabulary: return "Vocabulário"
            case .spelling: return "Ortografia"
            case .register: return "Registro"
            case .wordOrder: return "Ordem"
            case .style: return "Estilo"
            }
        }
    }

    struct CorrectionResult: Codable {
        let summary_pt: String
        let errors: [WritingError]
        let native_version_de: String
        let cefr_estimate: String?

        struct WritingError: Codable, Hashable {
            let excerpt: String                    // trecho original com problema
            let category: String                    // ErrorCategory.rawValue
            let explanation_pt: String              // explicação em PT
            let suggestion_de: String               // como deveria ser
            let citation: Citation?

            struct Citation: Codable, Hashable {
                let book_id: String
                let book_title: String
                let section_title: String?
                let page_start: Int
                let page_end: Int
            }
        }
    }

    func correct(
        _ text: String,
        prompt: String? = nil,
        levelCEFR: String? = nil
    ) async throws -> CorrectionResult {
        // 1. Retrieval: busca regras gramaticais para erros prováveis
        var context = ""
        if let retriever {
            let hits = (try? await retriever.retrieve(query: text, limit: 4)) ?? []
            if !hits.isEmpty {
                context = "Trechos de gramática (use como referência para citações nas correções):\n\n"
                    + hits.enumerated().map { idx, h in
                        "[Trecho \(idx + 1)] book_id=\(h.bookId) | livro=\"\(h.bookTitle)\" | seção=\"\(h.sectionTitle ?? "—")\" | páginas \(h.pageStart)-\(h.pageEnd)\n\n\(h.text.prefix(500))"
                    }.joined(separator: "\n\n")
            }
        }

        let system = """
        Você é um corretor experiente de alemão para falantes de português brasileiro.

        Receberá um texto escrito por um aluno (provavelmente B1-B2). Retorne APENAS
        JSON neste formato:

        {
          "summary_pt": "1-2 frases sobre a qualidade geral do texto.",
          "errors": [
            {
              "excerpt": "trecho original com o erro (até 80 chars)",
              "category": "grammar|vocabulary|spelling|register|wordOrder|style",
              "explanation_pt": "explicação em português (didática, 1-3 frases)",
              "suggestion_de": "como deveria ser",
              "citation": null OR {"book_id":"...","book_title":"...","section_title":"...","page_start":N,"page_end":N}
            }
          ],
          "native_version_de": "Reescrita do texto inteiro como um nativo escreveria, no mesmo registro.",
          "cefr_estimate": "A1/A2/B1/B2/C1/C2 — sua estimativa do nível atual"
        }

        Regras:
        - Liste no máximo 8 erros principais (priorize gravidade).
        - Se um erro é coberto por trechos fornecidos, inclua a citação preservando exatamente os campos.
        - Se não há trecho aplicável, deixe citation: null.
        - Não invente citações.
        """

        var userPrompt = "Texto do aluno:\n\n\"\"\"\n\(text)\n\"\"\"\n\n"
        if let prompt {
            userPrompt += "Prompt original: \(prompt)\n"
        }
        if let levelCEFR {
            userPrompt += "Nível-alvo do aluno: \(levelCEFR)\n"
        }
        if !context.isEmpty {
            userPrompt += "\n\(context)"
        }

        return try await llmClient.generateStructured(
            prompt: userPrompt,
            systemInstruction: system,
            responseType: CorrectionResult.self,
            responseJSONSchema: nil,
            temperature: 0.2
        )
    }
}
