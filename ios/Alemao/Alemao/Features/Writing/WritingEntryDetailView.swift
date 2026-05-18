import SwiftData
import SwiftUI

struct WritingEntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var entry: WritingEntry
    @State private var isCorrecting = false
    @State private var errorMessage: String?

    private var correction: WritingCorrector.CorrectionResult? {
        guard let json = entry.correctionJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WritingCorrector.CorrectionResult.self, from: data)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let p = entry.prompt {
                    Text("Prompt").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(p).font(.callout).italic()
                }

                Text("Seu texto").font(.headline).padding(.top, 4)
                Text(entry.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let correction {
                    correctionView(correction)
                } else {
                    VStack(spacing: 8) {
                        Button {
                            Task { await runCorrection() }
                        } label: {
                            if isCorrecting {
                                HStack { ProgressView(); Text("Corrigindo…") }
                            } else {
                                Label("Pedir correção", systemImage: "wand.and.stars")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isCorrecting)

                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(.red).font(.caption)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
        .navigationTitle("Entrada")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func correctionView(_ c: WritingCorrector.CorrectionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Correção").font(.headline)
                Spacer()
                if let cefr = c.cefr_estimate {
                    Text("Estimado: \(cefr)")
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            Text(c.summary_pt).font(.callout).foregroundStyle(.secondary)

            if !c.errors.isEmpty {
                Text("Pontos de atenção").font(.subheadline.bold()).padding(.top, 4)
                ForEach(Array(c.errors.enumerated()), id: \.offset) { _, err in
                    errorCard(err)
                }
            }

            Text("Versão como nativo escreveria").font(.subheadline.bold()).padding(.top, 4)
            Text(c.native_version_de)
                .font(.callout)
                .padding()
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func errorCard(_ err: WritingCorrector.CorrectionResult.WritingError) -> some View {
        let category = WritingCorrector.ErrorCategory(rawValue: err.category) ?? .grammar
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(category.label)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(colorFor(category).opacity(0.2))
                    .foregroundStyle(colorFor(category))
                    .clipShape(Capsule())
                Spacer()
            }
            Text("« \(err.excerpt) »")
                .font(.callout)
                .italic()
                .foregroundStyle(.secondary)
            Text(err.explanation_pt).font(.callout)
            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                Text(err.suggestion_de).font(.callout.bold())
            }
            if let cit = err.citation {
                CitationCard(
                    bookId: cit.book_id,
                    bookTitle: cit.book_title,
                    sectionTitle: cit.section_title,
                    pageStart: cit.page_start,
                    pageEnd: cit.page_end,
                    excerpt: ""
                )
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func colorFor(_ c: WritingCorrector.ErrorCategory) -> Color {
        switch c {
        case .grammar: return .red
        case .vocabulary: return .orange
        case .spelling: return .pink
        case .register: return .yellow
        case .wordOrder: return .purple
        case .style: return .blue
        }
    }

    @MainActor
    private func runCorrection() async {
        isCorrecting = true
        errorMessage = nil
        do {
            let client = GeminiClient()
            let retriever = LibraryDB.shared.map { Retriever(libraryDB: $0, llmClient: client) }
            let corrector = WritingCorrector(retriever: retriever, llmClient: client)
            let result = try await corrector.correct(entry.content, prompt: entry.prompt)
            let data = try JSONEncoder().encode(result)
            entry.correctionJSON = String(data: data, encoding: .utf8)
            entry.correctedAt = .now
            try modelContext.save()
        } catch let err as LLMError {
            errorMessage = err.localizedDescription
        } catch {
            errorMessage = "Erro: \(error.localizedDescription)"
        }
        isCorrecting = false
    }
}
