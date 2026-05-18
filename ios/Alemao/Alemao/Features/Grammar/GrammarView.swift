import SwiftData
import SwiftUI

/// Aba Gramática: lista os tópicos com seed lessons + botões para tutor e
/// geração on-demand.
struct GrammarView: View {
    @Query(sort: \GeneratedLesson.topicId) private var lessons: [GeneratedLesson]
    @State private var showGenerator = false

    private var seedLessons: [GeneratedLesson] {
        lessons.filter { $0.source == "seed" }
    }

    private var customLessons: [GeneratedLesson] {
        lessons.filter { $0.source == "on-demand" }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AskTutorView()
                    } label: {
                        Label("Pergunte ao tutor", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    Button {
                        showGenerator = true
                    } label: {
                        Label("Nova lição sob demanda", systemImage: "sparkles")
                    }
                }

                if !customLessons.isEmpty {
                    Section("Suas lições") {
                        ForEach(customLessons, id: \.id) { lesson in
                            NavigationLink {
                                LessonDetailView(lesson: lesson)
                            } label: {
                                LessonListRow(lesson: lesson)
                            }
                        }
                    }
                }

                if seedLessons.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Sem lições no bundle",
                            systemImage: "books.vertical",
                            description: Text(
                                "Rode `scripts/sync_content.sh` para incluir as 20 seed lessons " +
                                "e recompile o app."
                            )
                        )
                    }
                } else {
                    Section("Tópicos da biblioteca") {
                        ForEach(seedLessons, id: \.id) { lesson in
                            NavigationLink {
                                LessonDetailView(lesson: lesson)
                            } label: {
                                LessonListRow(lesson: lesson)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Gramática")
            .sheet(isPresented: $showGenerator) {
                GenerateLessonView()
            }
        }
    }
}

private struct LessonListRow: View {
    let lesson: GeneratedLesson
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title).font(.subheadline.bold())
                if !lesson.summary.isEmpty {
                    Text(lesson.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(lesson.levelCEFR)
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    GrammarView()
        .modelContainer(for: [GeneratedLesson.self], inMemory: true)
}
