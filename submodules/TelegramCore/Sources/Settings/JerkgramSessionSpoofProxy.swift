import Foundation
import Postbox
import SwiftSignalKit
import JerkgramCore

// Applies the Jerkgram session-spoof proxy to Telegram's proxy settings.
//
// The proxy preference is account-manager-level shared data, so toggling it
// routes the (re)connection of every account through the configured exit
// node. It is invoked from the Spoof settings tab and once at application
// launch, before accounts are (re)authorized, so a session created after a
// logout/login is established through the spoof node and appears under that
// country in Telegram's session list.

public func jerkgramSessionSpoofServerSettings() -> ProxyServerSettings? {
    let state = JerkgramSessionSpoofController.shared.currentState
    guard state.isValid else {
        return nil
    }
    let port = state.port
    let host = state.trimmedHost
    if state.isMtproto {
        guard let secret = JerkgramSessionSpoofController.hexData(state.secret) else {
            return nil
        }
        return ProxyServerSettings(host: host, port: port, connection: .mtp(secret: secret))
    } else {
        let username = state.username.isEmpty ? nil : state.username
        let password = state.password.isEmpty ? nil : state.password
        return ProxyServerSettings(host: host, port: port, connection: .socks5(username: username, password: password))
    }
}

public func jerkgramSessionSpoofProxySettings() -> ProxyServerSettings? {
    guard JerkgramSessionSpoofController.shared.currentState.enabled else {
        return nil
    }
    return jerkgramSessionSpoofServerSettings()
}

public func jerkgramApplySessionSpoofProxy(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, NoError> {
    let enabled = JerkgramSessionSpoofController.shared.currentState.enabled
    let spoofServer = jerkgramSessionSpoofServerSettings()
    if enabled, let server = spoofServer {
        if let data = try? JSONEncoder().encode(server) {
            JerkgramSessionSpoofController.shared.setLastAppliedServer(data)
        }
    }
    return updateProxySettingsInteractively(accountManager: accountManager) { current in
        var updated = current
        var previouslyApplied: ProxyServerSettings?
        if let data = JerkgramSessionSpoofController.shared.lastAppliedServer() {
            previouslyApplied = try? JSONDecoder().decode(ProxyServerSettings.self, from: data)
        }
        if enabled, let server = spoofServer {
            // Drop the previously applied spoof server if it has since been
            // edited, then make the current one active.
            if let previous = previouslyApplied, previous != server {
                updated.servers.removeAll { $0 == previous }
            }
            updated.enabled = true
            if !updated.servers.contains(server) {
                updated.servers.append(server)
            }
            updated.activeServer = server
        } else {
            // Spoof disabled or misconfigured: deactivate whichever spoof
            // server was previously applied (or is still configured),
            // leaving any other user-configured proxies alone.
            if previouslyApplied == nil {
                previouslyApplied = spoofServer
            }
            if let server = previouslyApplied, current.activeServer == server {
                updated.enabled = false
                updated.activeServer = nil
            }
            if spoofServer == nil {
                JerkgramSessionSpoofController.shared.setLastAppliedServer(nil)
            }
        }
        return updated
    }
}
