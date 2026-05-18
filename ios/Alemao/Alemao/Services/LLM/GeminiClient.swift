import Foundation

/// Cliente Gemini via REST (sem SDK oficial Swift).
///
/// Endpoints usados:
/// - POST /v1beta/models/{model}:generateContent          — texto + structured output
/// - POST /v1beta/models/{model}:batchEmbedContents       — embeddings em batch
final class GeminiClient: LLMClient {
    struct Config {
        var textModel: String = "gemini-2.5-flash"
        var embeddingModel: String = "gemini-embedding-001"
        var baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!
        var timeoutSeconds: Double = 60
    }

    var config: Config
    private let session: URLSession

    init(config: Config = Config(), session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - Public API

    func generateStructured<T: Decodable>(
        prompt: String,
        systemInstruction: String? = nil,
        responseType: T.Type,
        responseJSONSchema: Any? = nil,
        temperature: Double = 0.3
    ) async throws -> T {
        let body = buildGenerateContentBody(
            prompt: prompt,
            systemInstruction: systemInstruction,
            temperature: temperature,
            responseMIMEType: "application/json",
            responseJSONSchema: responseJSONSchema
        )
        let data = try await postJSON(
            path: "/v1beta/models/\(config.textModel):generateContent",
            body: body
        )
        let text = try extractFirstTextPart(from: data)
        guard let jsonData = text.data(using: .utf8) else {
            throw LLMError.invalidResponse("Texto não é UTF-8")
        }
        do {
            return try JSONDecoder().decode(T.self, from: jsonData)
        } catch {
            throw LLMError.invalidResponse("Falha ao decodificar JSON: \(error)")
        }
    }

    func generateText(
        prompt: String,
        systemInstruction: String? = nil,
        temperature: Double = 0.3
    ) async throws -> String {
        let body = buildGenerateContentBody(
            prompt: prompt,
            systemInstruction: systemInstruction,
            temperature: temperature,
            responseMIMEType: nil,
            responseJSONSchema: nil
        )
        let data = try await postJSON(
            path: "/v1beta/models/\(config.textModel):generateContent",
            body: body
        )
        return try extractFirstTextPart(from: data)
    }

    func embed(
        texts: [String],
        taskType: EmbeddingTaskType = .retrievalDocument,
        dimension: Int = 768
    ) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let requests: [[String: Any]] = texts.map { text in
            [
                "model": "models/\(config.embeddingModel)",
                "content": ["parts": [["text": text]]],
                "taskType": taskType.rawValue,
                "outputDimensionality": dimension,
            ]
        }
        let body: [String: Any] = ["requests": requests]
        let data = try await postJSON(
            path: "/v1beta/models/\(config.embeddingModel):batchEmbedContents",
            body: body
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let embeddings = json?["embeddings"] as? [[String: Any]] else {
            throw LLMError.invalidResponse("Sem campo 'embeddings'")
        }
        return try embeddings.map { item in
            guard let values = item["values"] as? [Double] else {
                throw LLMError.invalidResponse("Embedding sem 'values'")
            }
            return values.map { Float($0) }
        }
    }

    /// Faz uma chamada simples para validar a chave.
    func testConnection() async throws {
        _ = try await generateText(prompt: "Diga 'OK' em alemão.", temperature: 0)
    }

    // MARK: - Internal

    private func buildGenerateContentBody(
        prompt: String,
        systemInstruction: String?,
        temperature: Double,
        responseMIMEType: String?,
        responseJSONSchema: Any?
    ) -> [String: Any] {
        var body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": temperature,
            ],
        ]
        if let systemInstruction {
            body["systemInstruction"] = [
                "parts": [["text": systemInstruction]]
            ]
        }
        if var genConfig = body["generationConfig"] as? [String: Any] {
            if let mime = responseMIMEType {
                genConfig["responseMimeType"] = mime
            }
            if let schema = responseJSONSchema {
                genConfig["responseSchema"] = schema
            }
            body["generationConfig"] = genConfig
        }
        return body
    }

    private func extractFirstTextPart(from data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let candidates = json?["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            throw LLMError.invalidResponse("Sem candidates/content/parts")
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else {
            throw LLMError.invalidResponse("Resposta vazia")
        }
        return text
    }

    private func postJSON(path: String, body: [String: Any]) async throws -> Data {
        let apiKey: String
        do {
            apiKey = try APIKeyStore.shared.get(.gemini)
        } catch {
            throw LLMError.missingAPIKey
        }

        var components = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else {
            throw LLMError.badRequest("URL inválida")
        }

        var request = URLRequest(url: url, timeoutInterval: config.timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.invalidResponse("Sem HTTPURLResponse")
            }
            switch http.statusCode {
            case 200..<300:
                return data
            case 400:
                throw LLMError.badRequest(String(data: data, encoding: .utf8) ?? "")
            case 429:
                throw LLMError.rateLimited
            default:
                throw LLMError.serverError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
        } catch let err as LLMError {
            throw err
        } catch {
            throw LLMError.network(error)
        }
    }
}
