import SwiftUI
import WidgetKit

// MARK: - TimelineEntry

struct WordEntry: TimelineEntry {
    let date: Date
    let card: WidgetCard?
    let dueCount: Int

    static let placeholder = WordEntry(
        date: .now,
        card: WidgetCard(
            headword: "Wörterbuch",
            gender: "das",
            translation: "dicionário",
            nextReviewISO: nil
        ),
        dueCount: 0
    )
}

// MARK: - Provider

struct WordProvider: TimelineProvider {
    func placeholder(in context: Context) -> WordEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WordEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WordEntry>) -> Void) {
        let entry = currentEntry()
        // Renova a cada hora — quando o app revisar um card, ele chama
        // WidgetCenter.reloadAllTimelines() pra atualizar imediatamente.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> WordEntry {
        WordEntry(
            date: .now,
            card: WidgetStore.wordOfDay(),
            dueCount: WidgetStore.dueCount()
        )
    }
}

// MARK: - View

struct WordOfTheDayView: View {
    let entry: WordEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "character.book.closed")
                    .font(.caption2)
                Text("Palavra do dia")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            if let card = entry.card {
                HStack(spacing: 4) {
                    if let g = card.gender {
                        Text(g)
                            .font(.title3.bold())
                            .foregroundStyle(genderColor(g))
                    }
                    Text(card.headword)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(card.translation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 2)
                if entry.dueCount > 0 {
                    Label("\(entry.dueCount) pendentes", systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } else {
                Spacer()
                Label("Sem cards ainda", systemImage: "rectangle.stack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func genderColor(_ g: String) -> Color {
        switch g.lowercased() {
        case "der": return .blue
        case "die": return .red
        case "das": return .green
        default: return .secondary
        }
    }
}

// MARK: - Widget

struct WordOfTheDayWidget: Widget {
    let kind = "WordOfTheDayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WordProvider()) { entry in
            WordOfTheDayView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Palavra do dia")
        .description("Sua próxima palavra de vocabulário a revisar.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
