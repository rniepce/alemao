import SwiftUI

struct LessonDetailView: View {
    let lesson: GeneratedLesson

    private struct Example: Codable { let de: String; let pt: String; let note: String? }
    private struct Exercise: Codable {
        let question: String; let answer: String; let explanation: String?
    }
    /// Alias: usamos DecodedCitation do CitationCard.swift.
    private typealias Citation = DecodedCitation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(lesson.levelCEFR)
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                    Text(lesson.topicId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !lesson.summary.isEmpty {
                    Text(lesson.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let markdown = try? AttributedString(
                    markdown: lesson.explanationMD,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) {
                    Text(markdown).textSelection(.enabled)
                } else {
                    Text(lesson.explanationMD).textSelection(.enabled)
                }

                if let examples = decode([Example].self, from: lesson.examplesJSON), !examples.isEmpty {
                    SectionHeader(title: "Exemplos")
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(examples.enumerated()), id: \.offset) { _, ex in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.de).font(.body).bold()
                                Text(ex.pt).font(.subheadline).foregroundStyle(.secondary)
                                if let note = ex.note, !note.isEmpty {
                                    Text(note).font(.caption).italic().foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }

                if let exercises = decode([Exercise].self, from: lesson.exercisesJSON), !exercises.isEmpty {
                    SectionHeader(title: "Exercícios")
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(exercises.enumerated()), id: \.offset) { idx, ex in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(idx + 1). \(ex.question)")
                                    .font(.callout)
                                DisclosureGroup("Resposta") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(ex.answer).font(.callout.monospaced())
                                        if let e = ex.explanation, !e.isEmpty {
                                            Text(e).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }

                if let citations = decode([Citation].self, from: lesson.citationsJSON), !citations.isEmpty {
                    SectionHeader(title: "Citações nos livros")
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(citations, id: \.self) { c in
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
            }
            .padding()
        }
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.top, 4)
    }
}
