import Foundation

/// Lookup de uma palavra alemã com fallback em cascata:
/// 1. `DictionaryDB` (bundleado) — instantâneo, offline
/// 2. Wiktionary (futuro: live API)
/// 3. Gemini LLM — gera definição estruturada quando nada mais funcionar
///
/// Resultado é normalizado em `WordEntry`.
struct WordEntry: Codable, Hashable {
    let headword: String
    let gender: String?            // der, die, das (substantivos)
    let pos: String?               // noun, verb, adj, adv, prep, conj
    let translations: [String]     // PT
    let examples: [Example]
    let source: String             // "dictionary" | "gemini" | "wiktionary"

    struct Example: Codable, Hashable {
        let de: String
        let pt: String?
    }
}

final class WordLookup {
    let llmClient: LLMClient
    let dictionary: DictionaryDB?

    init(llmClient: LLMClient, dictionary: DictionaryDB? = DictionaryDB.shared) {
        self.llmClient = llmClient
        self.dictionary = dictionary
    }

    /// Estratégia em cascata. Retorna nil se todas as fontes falharem.
    func lookup(_ word: String, contextSentence: String? = nil) async -> WordEntry? {
        let cleaned = normalize(word)
        // 1. Dicionário bundleado
        if let dict = dictionary, let entries = try? dict.lookup(cleaned), let first = entries.first {
            return WordEntry(
                headword: first.headword,
                gender: first.gender,
                pos: first.pos,
                translations: first.translations,
                examples: first.examples.map {
                    WordEntry.Example(de: $0.de, pt: $0.pt)
                },
                source: "dictionary"
            )
        }
        // 2. Gemini fallback
        if let viaLLM = try? await llmLookup(cleaned, context: contextSentence) {
            return viaLLM
        }
        return nil
    }

    // MARK: - LLM

    /// Schema que o Gemini retorna.
    private struct LLMLookup: Decodable {
        let headword: String
        let gender: String?
        let pos: String?
        let translations: [String]
        let examples: [WordEntry.Example]
    }

    private func llmLookup(_ word: String, context: String?) async throws -> WordEntry {
        let system = """
        Você é um dicionário alemão→português. Dada uma palavra, retorne JSON com:
        - headword: forma de cabeçalho (substantivo → forma nominativa singular)
        - gender: "der", "die" ou "das" para substantivos, senão null
        - pos: "noun", "verb", "adj", "adv", "prep", "conj" ou null
        - translations: lista de traduções em português (1-5)
        - examples: 1-2 exemplos no formato [{"de": "...", "pt": "..."}]

        Retorne APENAS o JSON.
        """
        let userPrompt: String
        if let context, !context.isEmpty {
            userPrompt = "Palavra: \(word)\nContexto: \(context)"
        } else {
            userPrompt = "Palavra: \(word)"
        }
        let result: LLMLookup = try await llmClient.generateStructured(
            prompt: userPrompt,
            systemInstruction: system,
            responseType: LLMLookup.self,
            responseJSONSchema: nil,
            temperature: 0.1
        )
        return WordEntry(
            headword: result.headword,
            gender: result.gender,
            pos: result.pos,
            translations: result.translations,
            examples: result.examples,
            source: "gemini"
        )
    }

    private func normalize(_ s: String) -> String {
        // Remove pontuação na ponta + lowercase. Substantivos alemães começam
        // com maiúscula, mas o DictionaryDB lookup é case-insensitive (headword_lower).
        let trimmed = s.trimmingCharacters(in: CharacterSet.punctuationCharacters
                                                .union(CharacterSet.whitespaces))
        return trimmed
    }
}
