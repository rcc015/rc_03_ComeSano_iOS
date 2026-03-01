import Foundation
import WatchConnectivity

@MainActor
final class WatchConnector: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchConnector()

    struct Event: Equatable {
        let alimento: String
        let calorias: Double
        let timestamp: Date
    }

    @Published private(set) var lastEvent: Event?
    @Published private(set) var caloriasRecientes: Double = 0

    private enum Keys {
        static let alimento = "alimento"
        static let calorias = "calorias"
        static let timestamp = "timestamp"
    }

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func registrarConsumo(alimento: String, calorias: Double) {
        let payload: [String: Any] = [
            Keys.alimento: alimento,
            Keys.calorias: calorias,
            Keys.timestamp: Date().timeIntervalSince1970
        ]

        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("WatchConnector sendMessage error: \(error.localizedDescription)")
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let parsed = Self.parsePayload(message)
        guard let parsed else { return }
        Task { @MainActor in
            self.applyParsedPayload(parsed)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let parsed = Self.parsePayload(userInfo)
        guard let parsed else { return }
        Task { @MainActor in
            self.applyParsedPayload(parsed)
        }
    }

    private nonisolated static func parsePayload(_ datos: [String: Any]) -> (alimento: String, calorias: Double, timestamp: Date)? {
        guard let alimento = datos[Keys.alimento] as? String else { return nil }

        let calorias: Double
        if let value = datos[Keys.calorias] as? Double {
            calorias = value
        } else if let number = datos[Keys.calorias] as? NSNumber {
            calorias = number.doubleValue
        } else {
            return nil
        }

        let timestamp: Date
        if let raw = datos[Keys.timestamp] as? Double {
            timestamp = Date(timeIntervalSince1970: raw)
        } else if let number = datos[Keys.timestamp] as? NSNumber {
            timestamp = Date(timeIntervalSince1970: number.doubleValue)
        } else {
            timestamp = .now
        }

        return (alimento, calorias, timestamp)
    }

    private func applyParsedPayload(_ payload: (alimento: String, calorias: Double, timestamp: Date)) {
        caloriasRecientes += payload.calorias
        lastEvent = Event(alimento: payload.alimento, calorias: payload.calorias, timestamp: payload.timestamp)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
}
