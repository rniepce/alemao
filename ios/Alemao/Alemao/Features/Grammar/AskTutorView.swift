import SwiftUI

/// "Pergunte ao tutor": campo livre, busca via Retriever, resposta Markdown
/// com citações clicáveis (abre PDF).
struct AskTutorView: View {
    @State private var question: String = ""
    @State private var answer: LessonGenerator.TutorAnswer?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var elapsedMS: Int = 0

    /// Sugestões clicáveis quando ainda não houve pergunta.
    private let suggestions = [
        "Qual a diferença entre 'wenn' e 'als'?",
        "Como escolher entre Konjunktiv I e II?",
        "Quando uso 'es gibt' vs 'haben'?",
        "Por que diz-se 'dem Mann' e não 'den Mann'?",
        "Verbos com prefixo separável vs inseparável",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inputField
                    .padding(.horizontal)

                if isLoading {
                    HStack { Spacer(); ProgressView("Pesquisando nos livros…"); Spacer() }
                        .padding()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                if answer == nil && !isLoading && errorMessage == nil {
                    suggestionsSection
                }

                if let answer {
                    answerSection(answer)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Pergunte ao tutor")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var inputField: some View {
        HStack(alignment: .top) {
            TextField("Pergunte algo sobre gramática alemã", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .onSubmit(execute)
            Button(action: execute) {
                Image(systemName: "paperplane.fill")
                    .font(.title3)
            }
            .disabled(isLoading || question.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sugestões")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            ForEach(suggestions, id: \.self) { s in
                Button {
                    question = s
                    execute()
                } label: {
                    HStack {
                        Image(systemName: "questionmark.bubble")
                        Text(s)
                        Spacer()
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
        }
    }

    private func answerSection(_ answer: LessonGenerator.TutorAnswer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Resposta").font(.headline)
                Spacer()
                Text("\(elapsedMS) ms")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if let md = try? AttributedString(
                markdown: answer.answer_md,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(md).textSelection(.enabled)
            } else {
                Text(answer.answer_md).textSelection(.enabled)
            }

            if !answer.citations.isEmpty {
                Text("Citações nos livros")
                    .font(.headline)
                    .padding(.top, 8)
                ForEach(Array(answer.citations.enumerated()), id: \.offset) { _, c in
                    CitationCard(
                        bookId: c.book_id,
                        bookTitle: c.book_title,
                        sectionTitle: c.section_title,
                        pageStart: c.page_start,
                        pageEnd: c.page_end,
                        excerpt: c.excerpt
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    private func execute() {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !isLoading else { return }
        Task { await run(q) }
    }

    @MainActor
    private func run(_ q: String) async {
        guard let lib = LibraryDB.shared else {
            errorMessage = "Biblioteca não disponível."
            return
        }
        isLoading = true
        errorMessage = nil
        answer = nil
        let started = Date()
        do {
            let client = GeminiClient()
            let retriever = Retriever(libraryDB: lib, llmClient: client)
            let generator = LessonGenerator(retriever: retriever, llmClient: client)
            answer = try await generator.askTutor(question: q)
            elapsedMS = Int(Date().timeIntervalSince(started) * 1000)
        } catch let err as LLMError {
            errorMessage = err.localizedDescription
        } catch {
            errorMessage = "Erro: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack { AskTutorView() }
}
