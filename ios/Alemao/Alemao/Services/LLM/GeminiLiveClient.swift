import Foundation

/// Cliente WebSocket para Gemini Live API (speech-to-speech bidirecional).
///
/// Fluxo:
/// 1. `connect(setup:)` abre o WebSocket e envia mensagem de setup
/// 2. `sendAudio(pcm16:)` envia chunks PCM 16-bit @ 16 kHz mono
/// 3. `events` é um AsyncStream com eventos do servidor (audio, texto, turnComplete)
///
/// Audio in: 16-bit PCM, 16 kHz, mono
/// Audio out: 16-bit PCM, 24 kHz, mono (segundo a doc do Gemini Live)
final class GeminiLiveClient: NSObject, @unchecked Sendable {
    enum LiveError: LocalizedError {
        case missingAPIKey
        case notConnected
        case network(Error)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "Chave Gemini ausente."
            case .notConnected: return "Não conectado."
            case .network(let e): return "Rede: \(e.localizedDescription)"
            case .server(let m): return "Servidor: \(m)"
            }
        }
    }

    enum ServerEvent {
        case audioChunk(Data)       // PCM 16-bit, 24 kHz, mono
        case textDelta(String)
        case inputTranscript(String) // transcript do que o usuário falou (Gemini envia opcionalmente)
        case turnComplete
        case error(Error)
        case disconnected
    }

    struct Setup {
        var model: String = "gemini-3.1-flash-live-preview"
        var systemInstruction: String
        var voiceName: String? = "Aoede"  // vozes: Aoede, Charon, Fenrir, Kore, Puck
        var languageCode: String? = "de-DE"
    }

    /// Eventos vindos do servidor (consumir com `for await ev in client.events {}`).
    var events: AsyncStream<ServerEvent> { eventsContinuation.makeStream() }
    private let eventsContinuation = AsyncStreamContinuation<ServerEvent>()

    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    override init() {
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    // MARK: - Connection lifecycle

    func connect(setup: Setup) async throws {
        let apiKey: String
        do {
            apiKey = try APIKeyStore.shared.get(.gemini)
        } catch {
            throw LiveError.missingAPIKey
        }

        var components = URLComponents(
            string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
        )!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw LiveError.notConnected }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()

        // Inicia loop de recebimento
        receiveTask = Task { await self.receiveLoop() }

        // Envia setup
        var generationConfig: [String: Any] = [
            "response_modalities": ["AUDIO"],
        ]
        if let voice = setup.voiceName {
            generationConfig["speech_config"] = [
                "voice_config": ["prebuilt_voice_config": ["voice_name": voice]],
                "language_code": setup.languageCode ?? "de-DE",
            ]
        }

        let payload: [String: Any] = [
            "setup": [
                "model": "models/\(setup.model)",
                "generation_config": generationConfig,
                "system_instruction": [
                    "parts": [["text": setup.systemInstruction]]
                ],
            ]
        ]
        try await sendJSON(payload)
    }

    func disconnect() {
        receiveTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        eventsContinuation.yield(.disconnected)
        eventsContinuation.finish()
    }

    // MARK: - Sending

    /// Envia um chunk de áudio PCM 16-bit @ 16 kHz mono.
    func sendAudio(pcm16: Data) async throws {
        guard let _ = task else { throw LiveError.notConnected }
        let payload: [String: Any] = [
            "realtime_input": [
                "media_chunks": [
                    [
                        "mime_type": "audio/pcm;rate=16000",
                        "data": pcm16.base64EncodedString(),
                    ]
                ]
            ]
        ]
        try await sendJSON(payload)
    }

    /// Envia texto avulso (alternativa a áudio — útil para iniciar conversa).
    func sendText(_ text: String, endOfTurn: Bool = true) async throws {
        guard let _ = task else { throw LiveError.notConnected }
        let payload: [String: Any] = [
            "client_content": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [["text": text]],
                    ]
                ],
                "turn_complete": endOfTurn,
            ]
        ]
        try await sendJSON(payload)
    }

    // MARK: - Internal

    private func sendJSON(_ obj: [String: Any]) async throws {
        guard let task else { throw LiveError.notConnected }
        let data = try JSONSerialization.data(withJSONObject: obj)
        try await task.send(.data(data))
    }

    private func receiveLoop() async {
        guard task != nil else { return }
        await receiveOne()
    }

    private func receiveOne() async {
        guard let task else { return }
        do {
            let message = try await task.receive()
            switch message {
            case .data(let data):
                handleIncoming(data)
            case .string(let s):
                if let data = s.data(using: .utf8) { handleIncoming(data) }
            @unknown default:
                break
            }
            // Reagenda
            if !Task.isCancelled { await receiveOne() }
        } catch {
            eventsContinuation.yield(.error(LiveError.network(error)))
            eventsContinuation.yield(.disconnected)
            eventsContinuation.finish()
        }
    }

    private func handleIncoming(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // server_content { model_turn { parts: [...] } }
        if let sc = obj["serverContent"] as? [String: Any] ?? obj["server_content"] as? [String: Any] {
            if let modelTurn = (sc["modelTurn"] as? [String: Any]) ?? (sc["model_turn"] as? [String: Any]),
               let parts = modelTurn["parts"] as? [[String: Any]] {
                for part in parts {
                    if let inline = (part["inlineData"] as? [String: Any]) ?? (part["inline_data"] as? [String: Any]),
                       let b64 = inline["data"] as? String,
                       let audio = Data(base64Encoded: b64) {
                        eventsContinuation.yield(.audioChunk(audio))
                    }
                    if let text = part["text"] as? String, !text.isEmpty {
                        eventsContinuation.yield(.textDelta(text))
                    }
                }
            }
            // Input transcription (algumas configurações do Live retornam transcript do user)
            if let inputTrans = (sc["inputTranscription"] as? [String: Any])
                ?? (sc["input_transcription"] as? [String: Any]),
               let text = inputTrans["text"] as? String, !text.isEmpty {
                eventsContinuation.yield(.inputTranscript(text))
            }
            if (sc["turnComplete"] as? Bool == true) || (sc["turn_complete"] as? Bool == true) {
                eventsContinuation.yield(.turnComplete)
            }
        }

        if let err = obj["error"] as? [String: Any] {
            eventsContinuation.yield(.error(LiveError.server(String(describing: err))))
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension GeminiLiveClient: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {}

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        eventsContinuation.yield(.disconnected)
        eventsContinuation.finish()
    }
}

// MARK: - AsyncStream helper

/// Pequeno helper que mantém uma fila + continuation por consumidor único.
/// Usado para evitar capturar continuation antes que `makeStream()` seja chamado.
private final class AsyncStreamContinuation<Element>: @unchecked Sendable {
    private var buffer: [Element] = []
    private var continuations: [AsyncStream<Element>.Continuation] = []
    private var finished = false
    private let queue = DispatchQueue(label: "live.events")

    func makeStream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            queue.sync {
                if finished {
                    continuation.finish()
                    return
                }
                continuations.append(continuation)
                for item in buffer {
                    continuation.yield(item)
                }
                buffer.removeAll()
            }
        }
    }

    func yield(_ value: Element) {
        queue.sync {
            if finished { return }
            if continuations.isEmpty {
                buffer.append(value)
            } else {
                for c in continuations { c.yield(value) }
            }
        }
    }

    func finish() {
        queue.sync {
            finished = true
            for c in continuations { c.finish() }
            continuations.removeAll()
        }
    }
}
