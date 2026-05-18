import SwiftUI

struct ReadingDetailView: View {
    let reading: GeneratedReadingEntity
    @State private var showQuestions: Bool = false
    @State private var showGlossary: Bool = false

    private struct Glossary: Codable { let de: String; let pt: String }
    private struct Question: Codable { let question: String; let answer: String }

    private var glossary: [Glossary] {
        decode(reading.glossaryJSON)
    }
    private var questions: [Question] {
        decode(reading.questionsJSON)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(reading.levelCEFR)
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                    Spacer()
                    Text(reading.createdAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Texto principal com tap-to-translate
                TappableGermanText(reading.bodyDE)

                Divider()

                DisclosureGroup(
                    isExpanded: $showGlossary,
                    content: {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(glossary.enumerated()), id: \.offset) { _, g in
                                HStack(alignment: .top) {
                                    Text(g.de).font(.callout.bold())
                                    Text("→").foregroundStyle(.tertiary)
                                    Text(g.pt).font(.callout)
                                    Spacer()
                                }
                            }
                        }
                    },
                    label: { Label("Glossário (\(glossary.count))", systemImage: "character.book.closed") }
                )

                DisclosureGroup(
                    isExpanded: $showQuestions,
                    content: {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(questions.enumerated()), id: \.offset) { idx, q in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(idx + 1). \(q.question)").font(.callout)
                                    DisclosureGroup("Resposta") {
                                        Text(q.answer).font(.callout).foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    },
                    label: { Label("Perguntas de compreensão (\(questions.count))", systemImage: "questionmark.bubble") }
                )
            }
            .padding()
        }
        .navigationTitle(reading.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func decode<T: Decodable>(_ json: String) -> [T] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }
}
