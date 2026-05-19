import SwiftData
import SwiftUI

// PersistentModel é declarado em SwiftData e usado pela generic helper deleteAll(_:).

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]
    @State private var apiKeyInput: String = ""

    init() {}
    @State private var keySaved: Bool = false
    @State private var testStatus: TestStatus = .idle
    @State private var bookCount: Int = 0
    @State private var chunkCount: Int = 0
    @State private var dictEntryCount: Int = 0
    @State private var showSignOutConfirm: Bool = false

    private var user: User? { users.first }

    enum TestStatus {
        case idle, testing, success(String), failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let user {
                    Section("Conta Apple") {
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(user.displayName.isEmpty ? "Sem nome" : user.displayName)
                                    .font(.headline)
                                if let email = user.email {
                                    Text(email).font(.caption).foregroundStyle(.secondary)
                                }
                                if let level = user.levelCEFR {
                                    Text("Nível: \(level)").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Button("Sair", role: .destructive) {
                            showSignOutConfirm = true
                        }
                    }
                }

                Section("Gemini API") {
                    SecureField("Chave Gemini (AIza…)", text: $apiKeyInput)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    HStack {
                        Button("Salvar chave") {
                            saveKey()
                        }
                        .disabled(apiKeyInput.isEmpty)

                        Spacer()

                        if keySaved {
                            Label("Salva no Keychain", systemImage: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }

                    Button("Testar conexão") {
                        Task { await testConnection() }
                    }
                    .disabled(!keySaved && apiKeyInput.isEmpty)

                    switch testStatus {
                    case .idle:
                        EmptyView()
                    case .testing:
                        ProgressView("Testando…")
                    case .success(let msg):
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section("Conteúdo bundleado") {
                    LabeledContent("Livros", value: "\(bookCount)")
                    LabeledContent("Trechos indexados", value: "\(chunkCount)")
                    LabeledContent("Entradas de dicionário", value: "\(dictEntryCount)")
                }

                Section {
                    if let url = URL(string: "https://aistudio.google.com/apikey") {
                        Link("Obter chave Gemini gratuita →", destination: url)
                    }
                } footer: {
                    Text(
                        "Sua chave fica salva apenas no Keychain deste dispositivo. " +
                        "O app chama a API Gemini diretamente — sem backend intermediário."
                    )
                }
            }
            .navigationTitle("Ajustes")
            .onAppear(perform: load)
            .confirmationDialog(
                "Sair da conta?",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sair", role: .destructive) { signOut() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Você precisará fazer login com sua conta Apple novamente. Seu progresso fica salvo localmente.")
            }
        }
    }

    /// Logout completo: apaga User + todos os dados associados (decks, cards,
    /// lições, readings, escrita, conversas, SRS logs). O conteúdo bundleado
    /// (library.sqlite, dictionary.sqlite, seed JSONs) permanece — só as
    /// cópias materializadas em SwiftData são limpas. Próximo login dispara
    /// os Seed*Loaders novamente para repopular do bundle.
    private func signOut() {
        if let user { modelContext.delete(user) }

        // Cascata de limpeza: não há `inverse` no User, então deletamos cada
        // tipo de modelo de usuário explicitamente.
        deleteAll(VocabCard.self)
        deleteAll(Deck.self)
        deleteAll(GeneratedLesson.self)
        deleteAll(GeneratedReadingEntity.self)
        deleteAll(WritingEntry.self)
        deleteAll(ConversationSession.self)
        deleteAll(ReviewLog.self)

        try? modelContext.save()
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        do {
            try modelContext.delete(model: type)
        } catch {
            print("[signOut] Falha ao apagar \(type): \(error)")
        }
    }

    private func load() {
        keySaved = APIKeyStore.shared.exists(.gemini)
        if let lib = LibraryDB.shared {
            bookCount = (try? lib.allBooks().count) ?? 0
            chunkCount = (try? lib.chunkCount()) ?? 0
        }
        if let dict = DictionaryDB.shared {
            dictEntryCount = (try? dict.count()) ?? 0
        }
    }

    private func saveKey() {
        do {
            try APIKeyStore.shared.set(apiKeyInput, for: .gemini)
            apiKeyInput = ""
            keySaved = true
            testStatus = .idle
        } catch {
            testStatus = .failure("Não foi possível salvar: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func testConnection() async {
        // Permite testar com chave recém-digitada sem precisar salvar
        if !apiKeyInput.isEmpty, !keySaved {
            saveKey()
        }
        testStatus = .testing
        let client = GeminiClient()
        do {
            try await client.testConnection()
            testStatus = .success("Conexão OK")
        } catch {
            testStatus = .failure(error.localizedDescription)
        }
    }
}

#Preview {
    SettingsView()
}
