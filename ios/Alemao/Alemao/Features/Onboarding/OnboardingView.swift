import AuthenticationServices
import SwiftData
import SwiftUI

/// Fluxo de onboarding: 4 etapas
/// 1. Boas-vindas + 4 destaques
/// 2. Coleta de chave Gemini (passo obrigatório)
/// 3. Sign in with Apple (cria conta canônica)
/// 4. Teste de nivelamento opcional → atualiza `User.levelCEFR`
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    @State private var step: Step = .welcome
    @State private var apiKey: String = ""
    @State private var apiKeyTested: Bool = false
    @State private var apiKeyError: String?

    /// Credenciais Apple capturadas no passo `.signIn`; usadas para criar o `User` no fim.
    @State private var appleCredentials: AppleAuthService.Credentials?
    @State private var signInError: String?

    enum Step {
        case welcome, byok, signIn, placement
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .welcome: welcomeView
                    case .byok: byokView
                    case .signIn: signInView
                    case .placement: placementView
                    }
                }
                .padding()
            }
            .navigationTitle("Bem-vindo(a)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Alemão.")
                .font(.system(size: 40, weight: .bold))
            Text("Seu professor pessoal de alemão, com base nos livros que você tem e em IA generativa.")
                .font(.title3)
                .foregroundStyle(.secondary)
            FeatureRow(icon: "books.vertical.fill",
                       title: "Conteúdo dos seus livros",
                       description: "Acesso direto aos livros que importou no pipeline.")
            FeatureRow(icon: "sparkles",
                       title: "Lições sob demanda",
                       description: "Gera novas lições e exercícios sobre qualquer tópico.")
            FeatureRow(icon: "bubble.left.and.bubble.right.fill",
                       title: "Conversa por voz",
                       description: "Pratique speaking com role-plays imersivos.")
            FeatureRow(icon: "lock.shield.fill",
                       title: "Privado",
                       description: "Seus dados ficam no iCloud; chamadas à IA usam sua própria API key.")

            Button {
                step = .byok
            } label: {
                Text("Continuar").frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
    }

    // MARK: - Sign In

    private var signInView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Faça login").font(.title2.bold())
            Text(
                "Use sua conta Apple para identificar este usuário. Seu ID fica " +
                "associado ao seu progresso e sincroniza via iCloud entre seus aparelhos."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer().frame(height: 8)

            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: handleAppleSignIn
            )
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .cornerRadius(10)

            if let signInError {
                Label(signInError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if let creds = appleCredentials {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Bem-vindo, \(creds.displayName.isEmpty ? "" : "\(creds.displayName)!")", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    if let email = creds.email {
                        Text(email).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)

                HStack {
                    Button("Pular teste de nível") {
                        finish(withLevel: nil)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        step = .placement
                    } label: {
                        Text("Fazer teste de nível")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top)
            }

            Spacer()
            Text(
                "Não armazenamos sua senha. A Apple devolve apenas um identificador único " +
                "(`userIdentifier`) e, na primeira vez, seu nome e e-mail (que ficam só neste dispositivo)."
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        signInError = nil
        switch result {
        case .success(let authorization):
            do {
                let creds = try AppleAuthService.extract(from: authorization)
                appleCredentials = creds
            } catch {
                signInError = error.localizedDescription
            }
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            // Usuário cancelou — nada a fazer
            break
        case .failure(let error):
            signInError = error.localizedDescription
        }
    }

    // MARK: - BYOK

    private var byokView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sua chave Gemini").font(.title2.bold())
            Text(
                "Cole sua chave gratuita do Google AI Studio. Ela fica salva apenas no " +
                "Keychain deste dispositivo e nunca é enviada a um servidor nosso."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            SecureField("AIza…", text: $apiKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if let url = URL(string: "https://aistudio.google.com/apikey") {
                Link("Como obter uma chave grátis →", destination: url)
                    .font(.callout)
            }

            if let err = apiKeyError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button {
                Task { await saveAndTest() }
            } label: {
                Text(apiKeyTested ? "Chave validada — Continuar" : "Salvar e testar")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty && !apiKeyTested)
        }
    }

    @MainActor
    private func saveAndTest() async {
        if apiKeyTested {
            step = .signIn
            return
        }
        do {
            try APIKeyStore.shared.set(apiKey.trimmingCharacters(in: .whitespaces), for: .gemini)
            try await GeminiClient().testConnection()
            apiKeyTested = true
            apiKeyError = nil
        } catch {
            apiKeyError = error.localizedDescription
        }
    }

    // MARK: - Placement

    private var placementView: some View {
        if let creds = appleCredentials {
            return AnyView(
                PlacementTestRunner(
                    appleCredentials: creds,
                    isPresented: $isPresented
                )
                .environment(\.modelContext, modelContext)
            )
        } else {
            return AnyView(
                Text("Erro: sem credenciais Apple.").foregroundStyle(.red)
            )
        }
    }

    private func finish(withLevel level: String?) {
        guard let creds = appleCredentials else { return }
        let user = User(
            appleUserIdentifier: creds.userIdentifier,
            email: creds.email,
            displayName: creds.displayName,
            levelCEFR: level,
            nativeLanguage: "pt"
        )
        modelContext.insert(user)
        try? modelContext.save()
        isPresented = false
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
