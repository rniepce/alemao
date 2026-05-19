import SwiftData
import SwiftUI

/// Dashboard inicial: saudação, plano diário, atalhos.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]
    @Query private var allCards: [VocabCard]
    @Query private var sessions: [ConversationSession]
    @Query(sort: \GeneratedLesson.generatedAt, order: .reverse)
    private var lessons: [GeneratedLesson]
    @Query(sort: \WritingEntry.createdAt, order: .reverse)
    private var writingEntries: [WritingEntry]

    @State private var seedLoaded: Bool = false

    private var user: User? { users.first }

    private var dueCards: [VocabCard] {
        let now = Date()
        return allCards.filter { $0.nextReviewDate <= now }
    }

    /// Sugere uma lição não revisada ainda hoje
    private var todayLesson: GeneratedLesson? {
        lessons.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    streakCard
                    dailyPlan
                    if let lesson = todayLesson {
                        suggestedLessonCard(lesson)
                    }
                    quickStats
                }
                .padding()
            }
            .navigationTitle("Início")
            .task { await ensureSeedLessons() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.title2.bold())
            if let level = user?.levelCEFR {
                Text("Nível atual: \(level)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var greeting: String {
        let name = user?.displayName.isEmpty == false ? user!.displayName : "Você"
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Guten Morgen, \(name)!"
        case 12..<18: return "Guten Tag, \(name)!"
        case 18..<22: return "Guten Abend, \(name)!"
        default: return "Hallo, \(name)!"
        }
    }

    private var streakCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.title)
                .foregroundStyle(.orange)
            VStack(alignment: .leading) {
                Text("\(user?.streakDays ?? 0) dias")
                    .font(.title2.bold())
                Text("seguidos estudando")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(user?.xp ?? 0) XP")
                    .font(.callout.bold())
                Text("acumulados")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var dailyPlan: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plano de hoje").font(.headline)
            VStack(spacing: 8) {
                planTile(
                    title: "\(dueCards.count) cards de vocabulário",
                    icon: "rectangle.stack.fill",
                    color: dueCards.isEmpty ? .secondary : .blue,
                    isComplete: dueCards.isEmpty
                )
                planTile(
                    title: "1 lição de gramática",
                    icon: "character.book.closed.fill",
                    color: .indigo,
                    isComplete: false
                )
                planTile(
                    title: "5 minutos de conversação",
                    icon: "bubble.left.and.bubble.right.fill",
                    color: .pink,
                    isComplete: hasSpokenToday
                )
                planTile(
                    title: "1 entrada de escrita",
                    icon: "square.and.pencil",
                    color: .green,
                    isComplete: hasWrittenToday
                )
            }
        }
    }

    private var hasSpokenToday: Bool {
        let today = Calendar.current.startOfDay(for: .now)
        return sessions.contains { $0.startedAt >= today }
    }

    private var hasWrittenToday: Bool {
        let today = Calendar.current.startOfDay(for: .now)
        return writingEntries.contains { $0.createdAt >= today }
    }

    private func planTile(title: String, icon: String, color: Color, isComplete: Bool) -> some View {
        HStack {
            Image(systemName: isComplete ? "checkmark.circle.fill" : icon)
                .foregroundStyle(isComplete ? .green : color)
                .frame(width: 28)
            Text(title)
                .strikethrough(isComplete)
                .foregroundStyle(isComplete ? .secondary : .primary)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func suggestedLessonCard(_ lesson: GeneratedLesson) -> some View {
        NavigationLink {
            LessonDetailView(lesson: lesson)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Lição sugerida")
                        .font(.caption.bold())
                    Spacer()
                    Text(lesson.levelCEFR)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }
                Text(lesson.title).font(.headline)
                if !lesson.summary.isEmpty {
                    Text(lesson.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.15), Color.accentColor.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var quickStats: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resumo").font(.headline)
            HStack(spacing: 12) {
                statBubble(value: "\(allCards.count)", label: "cards")
                statBubble(value: "\(lessons.count)", label: "lições")
                statBubble(value: "\(sessions.count)", label: "conversas")
                statBubble(value: "\(writingEntries.count)", label: "textos")
            }
        }
    }

    private func statBubble(value: String, label: String) -> some View {
        VStack {
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Bootstrap

    @MainActor
    private func ensureSeedLessons() async {
        guard !seedLoaded else { return }
        seedLoaded = true
        // Upsert por launch: insere tópicos novos do bundle (no-op se já estiverem).
        try? SeedLessonLoader.load(into: modelContext)
    }
}

#Preview {
    HomeView()
        .modelContainer(
            for: [User.self, VocabCard.self, GeneratedLesson.self,
                  ConversationSession.self, WritingEntry.self],
            inMemory: true
        )
}
