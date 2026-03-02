import Foundation

#if os(iOS)
import AuthenticationServices
import UIKit

@MainActor
final class BackendWebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var currentSession: ASWebAuthenticationSession?

    func signInWithGoogle(baseURL: URL) async throws -> String {
        var components = URLComponents(url: baseURL.appending(path: "/auth/google/start"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "redirect_uri", value: "comesano://auth/callback")
        ]

        guard let loginURL = components?.url else {
            throw BackendAuthError.invalidBaseURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: loginURL, callbackURLScheme: "comesano") { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: BackendAuthError.missingCallback)
                    return
                }

                guard let token = Self.extractToken(from: callbackURL) else {
                    continuation.resume(throwing: BackendAuthError.missingToken)
                    return
                }

                continuation.resume(returning: token)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.currentSession = session

            guard session.start() else {
                self.currentSession = nil
                continuation.resume(throwing: BackendAuthError.couldNotStartSession)
                return
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }

    private static func extractToken(from callbackURL: URL) -> String? {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        if let token = queryItems.first(where: { $0.name == "token" })?.value, !token.isEmpty {
            return token
        }
        if let token = queryItems.first(where: { $0.name == "access_token" })?.value, !token.isEmpty {
            return token
        }

        return nil
    }
}

enum BackendAuthError: LocalizedError {
    case invalidBaseURL
    case couldNotStartSession
    case missingCallback
    case missingToken

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "URL del backend inválida."
        case .couldNotStartSession:
            return "No se pudo iniciar el login web."
        case .missingCallback:
            return "No se recibió callback del backend."
        case .missingToken:
            return "El backend no devolvió token de sesión."
        }
    }
}
#endif
