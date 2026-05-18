import SwiftUI

/// Tela de debug para validar end-to-end o RAG dentro do iPhone:
/// digita query → embed → FTS + cosine → RRF → mostra top hits com citações.
struct RetrievalDebugView: View {
    @State private var query: String = ""
    @State private var hits: [Retriever.Hit] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var elapsedMS: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Pergunta ou tópico (de/pt/en)", text: $query, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit(runQuery)
                Button {
                    runQuery()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding()

            if isLoading {
                ProgressView("Buscando…").padding()
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            }

            if !hits.isEmpty {
                HStack {
                    Text("\(hits.count) resultados em \(elapsedMS)ms")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)

                List(hits, id: \.chunkId) { hit in
                    HitRow(hit: hit)
                }
                .listStyle(.plain)
            } else if !isLoading && errorMessage == nil {
                ContentUnavailableView(
                    "Digite uma busca",
                    systemImage: "text.magnifyingglass",
                    description: Text("Exemplos: \"Akkusativ\", \"Konjunktiv II\", \"verbos separáveis\"")
                )
                .padding()
            }
        }
        .navigationTitle("Buscar nos livros")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runQuery() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !isLoading else { return }
        Task { await execute(q) }
    }

    @MainActor
    private func execute(_ q: String) async {
        guard let lib = LibraryDB.shared else {
            errorMessage = "library.sqlite não está no bundle."
            return
        }
        isLoading = true
        errorMessage = nil
        let started = Date()
        do {
            let retriever = Retriever(libraryDB: lib, llmClient: GeminiClient())
            hits = try await retriever.retrieve(query: q, limit: 8)
            elapsedMS = Int(Date().timeIntervalSince(started) * 1000)
        } catch let err as LLMError {
            errorMessage = err.localizedDescription
            hits = []
        } catch {
            errorMessage = "Erro: \(error.localizedDescription)"
            hits = []
        }
        isLoading = false
    }
}

private struct HitRow: View {
    let hit: Retriever.Hit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(hit.bookTitle)
                    .font(.subheadline.bold())
                Spacer()
                Text("score \(String(format: "%.3f", hit.score))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let s = hit.sectionTitle {
                Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 8) {
                Label("p.\(hit.pageStart)-\(hit.pageEnd)", systemImage: "doc.text")
                if let r = hit.ftsRank { Label("fts #\(r)", systemImage: "textformat.abc") }
                if let r = hit.denseRank { Label("vec #\(r)", systemImage: "wand.and.stars") }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Text(hit.text.prefix(400) + (hit.text.count > 400 ? "…" : ""))
                .font(.footnote)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { RetrievalDebugView() }
}
