import Foundation

/// Protocolo abstrato para clientes LLM. Permite trocar provider sem mexer nas features.
protocol LLMClient {
    /// Geração estruturada (JSON validado contra um Decodable).
    func generateStructured<T: Decodable>(
        prompt: String,
        systemInstruction: String?,
        responseType: T.Type,
        responseJSONSchema: Any?,
        temperature: Double
    ) async throws -> T

    /// Geração de texto livre.
    func generateText(
        prompt: String,
        systemInstruction: String?,
        temperature: Double
    ) async throws -> String

    /// Embeddings em batch.
    func embed(
        texts: [String],
        taskType: EmbeddingTaskType,
        dimension: Int
    ) async throws -> [[Float]]
}

enum EmbeddingTaskType: String {
    case retrievalDocument = "RETRIEVAL_DOCUMENT"
    case retrievalQuery = "RETRIEVAL_QUERY"
    case semanticSimilarity = "SEMANTIC_SIMILARITY"
    case classification = "CLASSIFICATION"
    case clustering = "CLUSTERING"
}

enum LLMError: LocalizedError {
    case missingAPIKey
    case badRequest(String)
    case rateLimited
    case serverError(Int, String)
    case invalidResponse(String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Chave da API não configurada. Vá em Ajustes."
        case .badRequest(let m): return "Requisição inválida: \(m)"
        case .rateLimited: return "Limite de requisições atingido. Aguarde alguns segundos."
        case .serverError(let code, let m): return "Erro do servidor \(code): \(m)"
        case .invalidResponse(let m): return "Resposta inválida: \(m)"
        case .network(let e): return "Falha de rede: \(e.localizedDescription)"
        }
    }
}
