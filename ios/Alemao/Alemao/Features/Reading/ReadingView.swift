import SwiftData
import SwiftUI

/// Aba Leitura: gerar textos sob demanda + lista de textos salvos.
struct ReadingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GeneratedReadingEntity.createdAt, order: .reverse)
    private var readings: [GeneratedReadingEntity]
    @State private var showGenerator = false
    @State private var seedLoaded = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showGenerator = true
                    } label: {
                        Label("Gerar novo texto", systemImage: "sparkles")
                    }
                }

                if readings.isEmpty {
                    ContentUnavailableView(
                        "Nenhum texto ainda",
                        systemImage: "doc.text",
                        description: Text("Gere um texto sob demanda para começar a praticar leitura.")
                    )
                } else {
                    Section("Textos") {
                        ForEach(readings, id: \.id) { reading in
                            NavigationLink {
                                ReadingDetailView(reading: reading)
                            } label: {
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(reading.title).font(.headline)
                                        Spacer()
                                        Text(reading.levelCEFR)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                    Text(reading.bodyDE.prefix(120))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Leitura")
            .sheet(isPresented: $showGenerator) {
                GenerateReadingSheet()
            }
            .task { loadSeedsIfNeeded() }
        }
    }

    private func loadSeedsIfNeeded() {
        guard !seedLoaded else { return }
        seedLoaded = true
        try? SeedReadingLoader.load(into: modelContext)
    }
}

private struct GenerateReadingSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var topic: String = ""
    @State private var level: String = "B1"
    @State private var wordCount: Double = 200
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var generated: GeneratedReadingEntity?

    private let levels = ["A1", "A2", "B1", "B2", "C1", "C2"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Sobre o que você quer ler?") {
                    TextField("Tópico (ex: viagem a Berlim)", text: $topic, axis: .vertical)
                        .lineLimit(1...3)
                    Picker("Nível", selection: $level) {
                        ForEach(levels, id: \.self) { Text($0).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text("Tamanho: \(Int(wordCount)) palavras")
                            .font(.caption)
                        Slider(value: $wordCount, in: 80...500, step: 20)
                    }
                }

                Section {
                    Button {
                        Task { await execute() }
                    } label: {
                        if isLoading {
                            HStack { ProgressView(); Text("Gerando…") }
                        } else {
                            Label("Gerar", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(isLoading || topic.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if let r = generated {
                    Section {
                        NavigationLink {
                            ReadingDetailView(reading: r)
                        } label: {
                            Label("Abrir '\(r.title)'", systemImage: "arrow.right.circle.fill")
                        }
                    }
                }
            }
            .navigationTitle("Novo texto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func execute() async {
        isLoading = true
        errorMessage = nil
        do {
            let client = GeminiClient()
            let retriever = LibraryDB.shared.map { Retriever(libraryDB: $0, llmClient: client) }
            let generator = ReadingGenerator(retriever: retriever, llmClient: client)
            let r = try await generator.generate(
                topic: topic.trimmingCharacters(in: .whitespaces),
                levelCEFR: level,
                wordCount: Int(wordCount)
            )
            let entity = GeneratedReadingEntity(
                title: r.title,
                levelCEFR: r.level_cefr,
                topic: topic,
                bodyDE: r.body_de,
                glossaryJSON: encode(r.glossary),
                questionsJSON: encode(r.comprehension_questions)
            )
            modelContext.insert(entity)
            try modelContext.save()
            generated = entity
        } catch let err as LLMError {
            errorMessage = err.localizedDescription
        } catch {
            errorMessage = "Erro: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func encode<T: Encodable>(_ v: T) -> String {
        guard let data = try? JSONEncoder().encode(v),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }
}

#Preview {
    ReadingView()
        .modelContainer(for: [GeneratedReadingEntity.self], inMemory: true)
}
