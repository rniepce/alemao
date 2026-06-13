import SwiftData
import SwiftUI

/// Aba "Tutor": lista de conversas de texto com a Lara + criar nova.
struct TutorListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TutorChat.lastMessageAt, order: .reverse) private var chats: [TutorChat]
    @Query private var users: [User]

    @State private var newChat: TutorChat?
    @State private var openNewChat = false

    private var defaultLevel: String { users.first?.levelCEFR ?? "B1" }

    var body: some View {
        NavigationStack {
            Group {
                if chats.isEmpty {
                    emptyState
                } else {
                    chatList
                }
            }
            .navigationTitle("Tutor")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: startNewChat) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(isPresented: $openNewChat) {
                if let newChat {
                    TutorChatView(chat: newChat)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                Text("Converse em alemão com a Lara")
                    .font(.title3.bold())
                Text("Bata papo sobre qualquer assunto. Ela corrige seus erros com carinho e te ensina quando perceber uma dificuldade.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .appCard(tone: .subtle)

            Button(action: startNewChat) {
                Label("Começar conversa", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var chatList: some View {
        List {
            ForEach(chats) { chat in
                NavigationLink {
                    TutorChatView(chat: chat)
                } label: {
                    chatRow(chat)
                }
            }
            .onDelete(perform: deleteChats)
        }
    }

    private func chatRow(_ chat: TutorChat) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(chat.title).font(.headline).lineLimit(1)
                Spacer()
                if let level = chat.levelCEFR {
                    LevelBadge(level, size: .small)
                }
            }
            if let last = chat.messages.last {
                Text(last.text_de)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(chat.lastMessageAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func startNewChat() {
        let chat = TutorChat(levelCEFR: defaultLevel)
        modelContext.insert(chat)
        try? modelContext.save()
        newChat = chat
        openNewChat = true
    }

    private func deleteChats(_ offsets: IndexSet) {
        for index in offsets { modelContext.delete(chats[index]) }
        try? modelContext.save()
    }
}

#Preview {
    TutorListView()
        .modelContainer(for: [TutorChat.self, User.self], inMemory: true)
}
