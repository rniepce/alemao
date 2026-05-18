import SwiftData
import SwiftUI

/// Conversa speech-to-speech via Gemini Live API.
struct ConversationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let scenario: Scenario

    @State private var status: Status = .idle
    @State private var transcript: [Turn] = []
    @State private var currentAssistantText: String = ""
    @State private var currentUserText: String = ""
    @State private var errorMessage: String?

    @State private var liveClient: GeminiLiveClient?
    @State private var audioCapture: AudioCapture?
    @State private var audioPlayer: AudioPlayer?
    @State private var sessionId: UUID?

    enum Status: Equatable {
        case idle, connecting, listening, error
    }

    struct Turn: Identifiable, Codable {
        let id = UUID()
        let role: String   // "user" | "assistant"
        var text: String
        let timestamp: Date

        enum CodingKeys: String, CodingKey { case role, text, timestamp }
    }

    var body: some View {
        VStack(spacing: 0) {
            scenarioHeader

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(transcript) { t in
                            turnBubble(t)
                        }
                        if !currentAssistantText.isEmpty {
                            turnBubble(Turn(role: "assistant", text: currentAssistantText, timestamp: .now))
                                .id("streaming")
                        }
                    }
                    .padding()
                }
                .onChange(of: transcript.count) { _, _ in
                    if let last = transcript.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            Divider()

            controlBar
        }
        .navigationTitle(scenario.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { stop() }
    }

    private var scenarioHeader: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(scenario.description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(scenario.level)
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
    }

    private var controlBar: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
            switch status {
            case .idle:
                Button {
                    Task { await startSession() }
                } label: {
                    Label("Iniciar conversa", systemImage: "mic.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
            case .connecting:
                HStack { ProgressView(); Text("Conectando…") }.padding()
            case .listening:
                HStack(spacing: 16) {
                    PulseDot(color: .red)
                    Text("Falando… solte o botão para encerrar")
                        .font(.callout)
                    Spacer()
                    Button(role: .destructive) {
                        stop()
                    } label: {
                        Image(systemName: "stop.circle.fill").font(.title2)
                    }
                }
                .padding()
            case .error:
                Button("Tentar novamente") { Task { await startSession() } }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.bottom)
    }

    @ViewBuilder
    private func turnBubble(_ t: Turn) -> some View {
        HStack {
            if t.role == "user" { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(t.role == "user" ? "Você" : scenario.title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(t.text)
                    .font(.callout)
                    .padding(10)
                    .background(t.role == "user" ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if t.role == "assistant" { Spacer(minLength: 40) }
        }
        .id(t.id)
    }

    // MARK: - Lifecycle

    @MainActor
    private func startSession() async {
        status = .connecting
        errorMessage = nil

        let client = GeminiLiveClient()
        let capture = AudioCapture()
        let player = AudioPlayer()
        self.liveClient = client
        self.audioCapture = capture
        self.audioPlayer = player

        do {
            try player.start()
            try await client.connect(setup: GeminiLiveClient.Setup(
                systemInstruction: scenario.systemPrompt
            ))
            // Pump audio capture → client
            capture.onChunk = { chunk in
                Task {
                    try? await client.sendAudio(pcm16: chunk)
                }
            }
            try await capture.start()
            status = .listening

            // Cria session no banco
            let session = ConversationSession(
                scenarioTitle: scenario.title,
                levelCEFR: scenario.level
            )
            modelContext.insert(session)
            sessionId = session.id

            // Consome eventos do servidor
            Task { await consumeEvents(client: client, player: player) }
        } catch {
            errorMessage = error.localizedDescription
            status = .error
            stop()
        }
    }

    private func consumeEvents(client: GeminiLiveClient, player: AudioPlayer) async {
        for await event in client.events {
            await MainActor.run {
                switch event {
                case .audioChunk(let data):
                    player.enqueue(pcm16: data)
                case .textDelta(let t):
                    currentAssistantText += t
                case .inputTranscript(let t):
                    currentUserText += t
                case .turnComplete:
                    flushPendingTurns()
                case .error(let e):
                    errorMessage = e.localizedDescription
                case .disconnected:
                    if status == .listening { status = .idle }
                }
            }
        }
    }

    @MainActor
    private func flushPendingTurns() {
        if !currentUserText.isEmpty {
            transcript.append(Turn(role: "user", text: currentUserText, timestamp: .now))
            currentUserText = ""
        }
        if !currentAssistantText.isEmpty {
            transcript.append(Turn(role: "assistant", text: currentAssistantText, timestamp: .now))
            currentAssistantText = ""
        }
        persistTranscript()
    }

    private func persistTranscript() {
        guard let sessionId else { return }
        let fetch = FetchDescriptor<ConversationSession>(predicate: #Predicate { $0.id == sessionId })
        if let session = try? modelContext.fetch(fetch).first {
            if let data = try? JSONEncoder().encode(transcript),
               let str = String(data: data, encoding: .utf8) {
                session.turnsJSON = str
            }
            try? modelContext.save()
        }
    }

    private func stop() {
        audioCapture?.stop()
        audioPlayer?.stop()
        liveClient?.disconnect()
        flushPendingTurns()
        if let sessionId {
            let fetch = FetchDescriptor<ConversationSession>(predicate: #Predicate { $0.id == sessionId })
            if let session = try? modelContext.fetch(fetch).first {
                session.endedAt = .now
                try? modelContext.save()
            }
        }
        status = .idle
    }
}

private struct PulseDot: View {
    let color: Color
    @State private var scale: CGFloat = 1.0
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    scale = 1.4
                }
            }
    }
}
