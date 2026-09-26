import Foundation

// Jerkgram session spoof ("the session appears from the chosen region").
//
// Telegram derives the country shown for a session from the IP address the
// connection is made from. This controller stores the proxy server that the
// account traffic is routed through; applying it (making it the active proxy
// in Telegram's proxy settings) is done on the TelegramCore side because the
// proxy preference lives in the account manager's shared data.
//
// The stored configuration always persists (UserDefaults) so that after the
// user logs out and back in the proxy is still in place: a freshly created
// session is then established through the spoof exit node.
// Application is gated by `enabled`.

public struct JerkgramSessionSpoofState: Equatable, Codable {
    public var enabled: Bool
    public var host: String
    public var port: Int32
    public var isMtproto: Bool
    public var username: String
    public var password: String
    public var secret: String

    public init(
        enabled: Bool = false,
        host: String = "",
        port: Int32 = 0,
        isMtproto: Bool = false,
        username: String = "",
        password: String = "",
        secret: String = ""
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
        self.isMtproto = isMtproto
        self.username = username
        self.password = password
        self.secret = secret
    }

    public var trimmedHost: String {
        return self.host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var hasValidPort: Bool {
        return self.port > 0 && self.port <= 65535
    }

    /// Whether the stored configuration is complete enough to be applied.
    public var isValid: Bool {
        guard !self.trimmedHost.isEmpty, self.hasValidPort else {
            return false
        }
        if self.isMtproto {
            return JerkgramSessionSpoofController.hexData(self.secret) != nil
        }
        return true
    }
}

private let jerkgramSessionSpoofDefaultsKey = "jerkgram.SessionSpoof.State"

public final class JerkgramSessionSpoofController {
    public static let shared = JerkgramSessionSpoofController()

    private let lock = NSLock()
    private var state: JerkgramSessionSpoofState
    private let defaults: UserDefaults

    private init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        if let data = defaults.data(forKey: jerkgramSessionSpoofDefaultsKey),
            let stored = try? JSONDecoder().decode(JerkgramSessionSpoofState.self, from: data) {
            self.state = stored
        } else {
            self.state = JerkgramSessionSpoofState()
        }
    }

    public var currentState: JerkgramSessionSpoofState {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state
    }

    public func update(_ transform: (inout JerkgramSessionSpoofState) -> Void) {
        self.lock.lock()
        var updated = self.state
        transform(&updated)
        self.state = updated
        self.lock.unlock()

        if let data = try? JSONEncoder().encode(updated) {
            self.defaults.set(data, forKey: jerkgramSessionSpoofDefaultsKey)
        }
    }

    public func setEnabled(_ enabled: Bool) {
        self.update { $0.enabled = enabled }
    }

    private var lastAppliedServerData: Data?

    /// Records the proxy server that was actually applied to Telegram's
    /// proxy settings, so it can be deactivated later even if the stored
    /// configuration has since been edited into an invalid state.
    public func setLastAppliedServer(_ server: Data?) {
        self.lock.lock()
        self.lastAppliedServerData = server
        self.lock.unlock()
    }

    public func lastAppliedServer() -> Data? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.lastAppliedServerData
    }

    /// Decodes a hex string (whitespace tolerated) into raw bytes, used for
    /// MTProto proxy secrets.
    public static func hexData(_ string: String) -> Data? {
        let cleaned = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty, cleaned.count % 2 == 0 else {
            return nil
        }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(after: index)
            guard let byte = UInt8(cleaned[index ..< nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = cleaned.index(after: nextIndex)
        }
        return data
    }
}
