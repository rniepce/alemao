import AuthenticationServices
import Foundation

/// Serviço utilitário para Sign in with Apple.
///
/// O `userIdentifier` retornado pela Apple é estável por Apple ID em todos os
/// dispositivos e sobrevive a reinstalações do app — é a chave canônica para
/// identificar o usuário.
///
/// **Importante:** `email` e `fullName` só vêm na PRIMEIRA autenticação.
/// Logins subsequentes retornam apenas o `userIdentifier`. Por isso salvamos
/// tudo na primeira vez.
enum AppleAuthService {
    struct Credentials {
        let userIdentifier: String
        let email: String?
        let givenName: String?
        let familyName: String?

        var displayName: String {
            [givenName, familyName].compactMap { $0 }.joined(separator: " ")
        }
    }

    enum AuthError: LocalizedError {
        case missingIdentifier
        case unknownCredentialType
        case canceled
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .missingIdentifier: return "Apple ID não retornou um identificador."
            case .unknownCredentialType: return "Tipo de credencial desconhecido."
            case .canceled: return "Login cancelado."
            case .underlying(let e): return e.localizedDescription
            }
        }
    }

    /// Extrai credenciais de uma autorização recebida pelo SignInWithAppleButton.
    static func extract(from authorization: ASAuthorization) throws -> Credentials {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.unknownCredentialType
        }
        guard !credential.user.isEmpty else {
            throw AuthError.missingIdentifier
        }
        return Credentials(
            userIdentifier: credential.user,
            email: credential.email,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName
        )
    }

    /// Verifica o estado de credenciais salvas (notFound, revoked, authorized, etc).
    /// Útil para detectar se o usuário revogou o acesso no Settings → Apple ID.
    static func currentState(for userIdentifier: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        let provider = ASAuthorizationAppleIDProvider()
        return await withCheckedContinuation { continuation in
            provider.getCredentialState(forUserID: userIdentifier) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }
}
