import SwiftData
import SwiftUI

/// Gera uma nova lição on-demand para um tópico arbitrário e a salva no
/// SwiftData como `GeneratedLesson` (source = "on-demand").
struct GenerateLessonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var topic: String = ""
    @State private var level: String = "B1"
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var generated: GeneratedLesson?

    private let levels = ["A1", "A2", "B1", "B2", "C1", "C2"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Sobre o que você quer aprender?") {
                    TextField("Ex: Konjunktiv II em pedidos polidos", text: $topic, axis: .vertical)
                        .lineLimit(1...3)
                    Picker("Nível CEFR", selection: $level) {
                        ForEach(levels, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section {
                    Button {
                        Task { await execute() }
                    } label: {
                        if isLoading {
                            HStack { ProgressView(); Text("Gerando…") }
                        } else {
                            Label("Gerar lição", systemImage: "sparkles")
                        }
                    }
                    .disabled(isLoading || topic.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                if let lesson = generated {
                    Section {
                        NavigationLink {
                            LessonDetailView(lesson: lesson)
                        } label: {
                            Label("Abrir lição '\(lesson.title)'", systemImage: "arrow.right.circle.fill")
                        }
                    } footer: {
                        Text("A lição foi salva e estará disponível na aba Início.")
                    }
                }
            }
            .navigationTitle("Nova lição")
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
        let t = topic.trimmingCharacters(in: .whitespaces)
        guard let lib = LibraryDB.shared else {
            errorMessage = "Biblioteca não disponível."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let client = GeminiClient()
            let retriever = Retriever(libraryDB: lib, llmClient: client)
            let generator = LessonGenerator(retriever: retriever, llmClient: client)
            let content = try await generator.generateLesson(topic: t, level: level)

            let lesson = GeneratedLesson(
                topicId: slugify(t),
                title: content.title,
                levelCEFR: level,
                summary: content.summary,
                explanationMD: content.explanation_md,
                examplesJSON: LessonGenerator.encodeJSON(content.examples),
                exercisesJSON: LessonGenerator.encodeJSON(content.exercises),
                citationsJSON: LessonGenerator.encodeJSON(content.citations),
                generatedAt: .now,
                source: "on-demand"
            )
            modelContext.insert(lesson)
            try modelContext.save()
            generated = lesson
        } catch let err as LLMError {
            errorMessage = err.localizedDescription
        } catch {
            errorMessage = "Erro: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func slugify(_ s: String) -> String {
        let lower = s.lowercased()
        let allowed = lower.map { c -> Character in
            if c.isLetter || c.isNumber { return c }
            return "-"
        }
        return String(allowed).split(separator: "-").joined(separator: "-")
    }
}

#Preview {
    GenerateLessonView()
        .modelContainer(for: [GeneratedLesson.self], inMemory: true)
}
