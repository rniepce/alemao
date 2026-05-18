import AVFoundation
import SwiftData
import SwiftUI

/// Popup compacto que mostra resultado de lookup de uma palavra.
/// Inclui botão "adicionar ao deck" e play de áudio TTS nativo (de-DE).
struct WordLookupPopup: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let word: String
    let contextSentence: String?
    let sourceChunkId: String?
    let sourceBookId: String?
    let sourcePage: Int?

    @State private var entry: WordEntry?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var savedToDeck: Bool = false

    init(
        word: String,
        contextSentence: String? = nil,
        sourceChunkId: String? = nil,
        sourceBookId: String? = nil,
        sourcePage: Int? = nil
    ) {
        self.word = word
        self.contextSentence = contextSentence
        self.sourceChunkId = sourceChunkId
        self.sourceBookId = sourceBookId
        self.sourcePage = sourcePage
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Buscando…").padding()
                } else if let entry {
                    entryView(entry)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Não encontrado",
                        systemImage: "questionmark.bubble",
                        description: Text(errorMessage)
                    )
                } else {
                    ContentUnavailableView("Sem resultados", systemImage: "questionmark")
                }
            }
            .navigationTitle(word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func entryView(_ entry: WordEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    if let gender = entry.gender {
                        Text(gender)
                            .font(.title3.bold())
                            .foregroundStyle(colorForGender(gender))
                    }
                    Text(entry.headword)
                        .font(.title2.bold())
                    Spacer()
                    Button {
                        speak(entry.headword)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                    }
                }

                if let pos = entry.pos {
                    Text(pos.uppercased())
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Traduções").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(Array(entry.translations.enumerated()), id: \.offset) { _, t in
                        Text("• \(t)").font(.body)
                    }
                }

                if !entry.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Exemplos").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(Array(entry.examples.enumerated()), id: \.offset) { _, ex in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.de).font(.callout)
                                if let pt = ex.pt {
                                    Text(pt).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.bottom, 2)
                        }
                    }
                }

                HStack {
                    Text("Fonte: \(entry.source)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }

                Button {
                    addToDeck(entry)
                } label: {
                    if savedToDeck {
                        Label("Adicionada ao deck", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("Adicionar ao deck", systemImage: "plus.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(savedToDeck)
            }
            .padding()
        }
    }

    private func colorForGender(_ g: String) -> Color {
        switch g.lowercased() {
        case "der": return .blue
        case "die": return .red
        case "das": return .green
        default: return .secondary
        }
    }

    @MainActor
    private func load() async {
        let client = GeminiClient()
        let lookup = WordLookup(llmClient: client)
        if let result = await lookup.lookup(word, contextSentence: contextSentence) {
            entry = result
        } else {
            errorMessage = "Sem entrada no dicionário e Gemini falhou."
        }
        isLoading = false
    }

    private func speak(_ text: String) {
        let synth = AVSpeechSynthesizer.shared
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        utterance.rate = 0.45
        synth.speak(utterance)
    }

    private func addToDeck(_ entry: WordEntry) {
        let card = VocabCard(
            headword: entry.headword,
            gender: entry.gender,
            translation: entry.translations.first ?? "",
            exampleDE: entry.examples.first?.de,
            examplePT: entry.examples.first?.pt,
            sourceChunkId: sourceChunkId,
            sourceBookId: sourceBookId,
            sourcePage: sourcePage
        )
        modelContext.insert(card)
        try? modelContext.save()
        savedToDeck = true
    }
}

extension AVSpeechSynthesizer {
    /// Singleton para evitar deinit precoce do synth durante speak.
    static let shared = AVSpeechSynthesizer()
}
