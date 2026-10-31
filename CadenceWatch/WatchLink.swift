import CadenceCore
import Foundation
import WatchConnectivity

/// WatchConnectivity on the watch (design #339, section 4): the plan arrives as
/// application context; operations and acknowledgements travel as queued user
/// info, with `sendMessage` as a fast path while the phone is reachable.
/// Redelivery is harmless: the sync engine ignores operations it has seen.
@MainActor
final class WatchLink: NSObject {
    static let shared = WatchLink()
    private weak var model: WatchSessionModel?

    func activate(_ model: WatchSessionModel) {
        self.model = model
        model.send = { [weak self] wire in self?.send(wire) }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ wire: WatchWire) {
        guard WCSession.isSupported(), let message = try? wire.dictionary() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in }
        }
        switch wire {
        case .operations:
            // Always queued too: the fast path is best effort.
            session.transferUserInfo(message)
        case .ack, .requestPlan, .join:
            if !session.isReachable { session.transferUserInfo(message) }
        case .plan:
            break
        }
    }

    private func deliver(_ dictionary: [String: Any]) {
        guard let wire = WatchWire.decode(dictionary) else { return }
        model?.receive(wire)
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.deliver(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.deliver(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.deliver(userInfo) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.deliver(message) }
    }
}
