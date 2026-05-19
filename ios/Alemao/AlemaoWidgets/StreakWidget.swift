import SwiftUI
import WidgetKit

struct StreakEntry: TimelineEntry {
    let date: Date
    let streakDays: Int
    let xp: Int
    let dueCount: Int
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: .now, streakDays: 7, xp: 120, dueCount: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let entry = currentEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> StreakEntry {
        StreakEntry(
            date: .now,
            streakDays: WidgetStore.streakDays(),
            xp: WidgetStore.xp(),
            dueCount: WidgetStore.dueCount()
        )
    }
}

struct StreakView: View {
    let entry: StreakEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            small
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            Text("🔥 \(entry.streakDays)d · \(entry.dueCount) pendentes")
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text("Streak").font(.caption2.bold())
                Spacer()
            }
            Text("\(entry.streakDays)d")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.orange)
            Spacer(minLength: 2)
            HStack(spacing: 8) {
                Label("\(entry.xp)", systemImage: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                if entry.dueCount > 0 {
                    Label("\(entry.dueCount)", systemImage: "rectangle.stack.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var circular: some View {
        ZStack {
            Circle().stroke(Color.orange.opacity(0.3), lineWidth: 4)
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                Text("\(entry.streakDays)")
                    .font(.title3.bold())
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "flame.fill")
                Text("\(entry.streakDays) dias").bold()
            }
            HStack {
                Text("\(entry.xp) XP")
                Spacer()
                Text("\(entry.dueCount) pendentes")
            }
            .font(.caption2)
        }
    }
}

struct StreakWidget: Widget {
    let kind = "StreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Dias seguidos estudando + revisões pendentes.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}
