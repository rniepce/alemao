import SwiftData
import SwiftUI

@main
struct AlemaoApp: App {
    /// Container compartilhado para dados do usuário (sincronizado via CloudKit).
    /// O conteúdo bundleado (library.sqlite + dictionary.sqlite + seed_lessons.json)
    /// fica fora do SwiftData — é carregado via GRDB pelo `LibraryDB`.
    let userDataContainer: ModelContainer = {
        let schema = Schema([
            User.self,
            VocabCard.self,
            Deck.self,
            GeneratedLesson.self,
            GeneratedReadingEntity.self,
            WritingEntry.self,
            ConversationSession.self,
            ReviewLog.self,
        ])
        // CloudKit sync é ligado por padrão (.automatic) quando o app tem
        // entitlements de iCloud. Em dev, cai pra storage local.
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Falha ao criar ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(userDataContainer)
        }
    }
}
