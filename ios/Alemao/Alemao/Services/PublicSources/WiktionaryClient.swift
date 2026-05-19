import Foundation

/// Cliente para o Wiktionary alemão. Busca definições de palavras alemãs via
/// a MediaWiki API oficial. Sem autenticação, sem rate limits agressivos.
///
/// Endpoint: https://de.wiktionary.org/w/api.php
/// Action: query com prop=extracts (texto plano sem markup) ou prop=revisions
/// (wikitext bruto para parsing mais estruturado).
///
/// Estratégia: tentamos primeiro `prop=extracts` para texto plain; se vier
/// vazio (palavra não tem entrada), retornamos nil. O parsing de wikitext
/// estruturado seria mais rico mas exige bem mais código.
final class WiktionaryClient {
    static let shared = WiktionaryClient()

    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = URL(string: "https://de.wiktionary.org/w/api.php")!
    }

    enum WiktError: LocalizedError {
        case network(Error)
        case decoding(String)
        case notFound

        var errorDescription: String? {
            switch self {
            case .network(let e): return "Wiktionary: \(e.localizedDescription)"
            case .decoding(let m): return "Wiktionary: \(m)"
            case .notFound: return "Wiktionary: palavra não encontrada"
            }
        }
    }

    /// Busca uma palavra no Wiktionary alemão e retorna definições estruturadas.
    /// Capitaliza substantivos (no DE, todos começam com maiúscula).
    func lookup(_ word: String) async throws -> WordEntry? {
        let term = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }

        // Tenta a forma exata + capitalizada (substantivos)
        let candidates = [term, term.capitalizedFirstLetter()]
        for candidate in Set(candidates) {
            if let entry = try? await fetchOne(candidate) {
                return entry
            }
        }
        return nil
    }

    // MARK: - Private

    private func fetchOne(_ title: String) async throws -> WordEntry? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "titles", value: title),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Alemao/0.1 (https://github.com/rniepce/alemao)", forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            let (responseData, _) = try await session.data(for: request)
            data = responseData
        } catch {
            throw WiktError.network(error)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WiktError.decoding("Resposta não-JSON")
        }
        guard let query = json["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any] else {
            return nil
        }
        // pages é um dict de "pageId": {...}. Pegamos o primeiro.
        for (_, value) in pages {
            guard let page = value as? [String: Any] else { continue }
            // Páginas inexistentes têm `missing` key
            if page["missing"] != nil { return nil }
            guard let extract = page["extract"] as? String, !extract.isEmpty else {
                continue
            }
            return Self.parseExtract(extract, headword: title)
        }
        return nil
    }

    /// Parse heurístico do extract plain-text retornado pelo Wiktionary alemão.
    /// O formato típico tem seções como "Substantiv, m", "Bedeutungen:", "Übersetzungen",
    /// etc. Extraímos as informações principais.
    static func parseExtract(_ text: String, headword: String) -> WordEntry {
        var gender: String? = nil
        var pos: String? = nil
        var translations: [String] = []
        var examples: [WordEntry.Example] = []

        // Detecta tipo + gênero
        // Exemplos: "Substantiv, m", "Substantiv, f", "Substantiv, n", "Verb",
        //           "Adjektiv", "Adverb"
        if let match = text.range(of: #"Substantiv,\s*([mfn])"#, options: .regularExpression) {
            let str = String(text[match])
            if str.hasSuffix("m") {
                gender = "der"
            } else if str.hasSuffix("f") {
                gender = "die"
            } else if str.hasSuffix("n") {
                gender = "das"
            }
            pos = "noun"
        } else if text.contains("Substantiv") {
            pos = "noun"
        } else if text.contains("Verb") {
            pos = "verb"
        } else if text.contains("Adjektiv") {
            pos = "adj"
        } else if text.contains("Adverb") {
            pos = "adv"
        } else if text.contains("Präposition") {
            pos = "prep"
        }

        // Bedeutungen (significados) — pega linhas após "Bedeutungen:"
        if let range = text.range(of: "Bedeutungen:") {
            let after = String(text[range.upperBound...])
            // Próxima seção (terminator) começa com palavra que termina com ":"
            let sectionEnd = after.range(of: #"\n[A-ZÄÖÜ][\w\säöüÄÖÜß-]+:"#, options: .regularExpression)?.lowerBound ?? after.endIndex
            let bedeutungenBlock = String(after[..<sectionEnd])
            for rawLine in bedeutungenBlock.split(separator: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                // Linhas tipo "[1] Mensch der weiblichen Art..."
                let cleaned = line
                    .replacingOccurrences(of: #"^\[\d+(\,\s*\d+)*\]\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    translations.append(cleaned)
                }
                if translations.count >= 5 { break }
            }
        }

        // Beispiele (exemplos)
        if let range = text.range(of: "Beispiele:") {
            let after = String(text[range.upperBound...])
            let sectionEnd = after.range(of: #"\n[A-ZÄÖÜ][\w\säöüÄÖÜß-]+:"#, options: .regularExpression)?.lowerBound ?? after.endIndex
            let block = String(after[..<sectionEnd])
            for rawLine in block.split(separator: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                let cleaned = line
                    .replacingOccurrences(of: #"^\[\d+\]\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    examples.append(WordEntry.Example(de: cleaned, pt: nil))
                }
                if examples.count >= 3 { break }
            }
        }

        return WordEntry(
            headword: headword,
            gender: gender,
            pos: pos,
            translations: translations,
            examples: examples,
            source: "wiktionary"
        )
    }
}

private extension String {
    func capitalizedFirstLetter() -> String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
