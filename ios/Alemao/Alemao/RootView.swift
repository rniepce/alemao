import AuthenticationServices
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]
    @State private var showOnboarding: Bool = false
    @State private var credentialChecked: Bool = false

    var body: some View {
        Group {
            if users.isEmpty {
                OnboardingPlaceholder()
                    .sheet(isPresented: $showOnboarding) {
                        OnboardingView(isPresented: $showOnboarding)
                            .interactiveDismissDisabled(true)
                    }
                    .onAppear { showOnboarding = true }
            } else {
                MainTabView()
                    .task { await checkAppleCredentialIfNeeded() }
            }
        }
    }

    /// No boot, verifica se o Apple ID ainda está autorizado. Se o usuário
    /// revogou no Settings → Apple ID → Apps Using Apple ID, força re-login.
    @MainActor
    private func checkAppleCredentialIfNeeded() async {
        guard !credentialChecked, let user = users.first,
              let identifier = user.appleUserIdentifier else {
            credentialChecked = true
            return
        }
        let state = await AppleAuthService.currentState(for: identifier)
        credentialChecked = true
        if state == .revoked || state == .notFound {
            // Apaga o User → próximo launch volta pro onboarding
            modelContext.delete(user)
            try? modelContext.save()
        }
    }
}

/// Splash mostrado enquanto a sheet de onboarding cobre a tela.
private struct OnboardingPlaceholder: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            Text("Alemão").font(.largeTitle.bold())
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MainTabView: View {
    @State private var selectedTab: Tab = .home

    enum Tab: Hashable {
        case home, tutor, vocabulary, grammar, reading, writing, speaking, library, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Início", systemImage: "house.fill") }
                .tag(Tab.home)

            TutorListView()
                .tabItem { Label("Tutor", systemImage: "bubble.left.and.text.bubble.right.fill") }
                .tag(Tab.tutor)

            VocabularyView()
                .tabItem { Label("Vocab", systemImage: "rectangle.stack.fill") }
                .tag(Tab.vocabulary)

            GrammarView()
                .tabItem { Label("Gramática", systemImage: "character.book.closed.fill") }
                .tag(Tab.grammar)

            ReadingView()
                .tabItem { Label("Leitura", systemImage: "doc.text") }
                .tag(Tab.reading)

            WritingView()
                .tabItem { Label("Escrita", systemImage: "square.and.pencil") }
                .tag(Tab.writing)

            SpeakingView()
                .tabItem { Label("Fala", systemImage: "waveform") }
                .tag(Tab.speaking)

            LibraryView()
                .tabItem { Label("Biblioteca", systemImage: "books.vertical.fill") }
                .tag(Tab.library)

            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gear") }
                .tag(Tab.settings)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(
            for: [User.self, VocabCard.self, Deck.self, GeneratedLesson.self,
                  GeneratedReadingEntity.self, WritingEntry.self,
                  ConversationSession.self, TutorChat.self, ReviewLog.self],
            inMemory: true
        )
}
