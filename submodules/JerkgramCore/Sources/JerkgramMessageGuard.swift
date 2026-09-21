import Foundation

// Jerkgram write-ahead guard for inbound messages.
//
// The capture hooks fire when Telegram applies a deletion or an edit, and
// everything they know about the removed message comes from Postbox at that
// moment. Whenever the store cannot resolve the message any more there is
// nothing left to record — but that is exactly what happens after the app
// stayed closed: a replayed difference can deliver a message and its deletion
// in one batch, and a global-id deletion can reference messages the store no
// longer maps.
//
// The guard keeps a bounded copy of the text of the messages the app actually
// received, so the deletion hook can still record what was removed. It is
// deliberately memory-only: it runs inside Postbox transactions and must never
// block them on disk I/O, while the JSONL event log remains the authoritative
// history. Because it is a recent-window fallback, both capacities are counted
// in messages, not in time.

public struct JerkgramIncomingMessageNote {
    public let chatPeerId: Int64
    public let messageNamespace: Int32
    public let messageId: Int32
    public let globallyUniqueId: Int64?
    public let senderPeerId: Int64?
    public let timestampMs: Int64
    public let text: String

    public init(
        chatPeerId: Int64,
        messageNamespace: Int32,
        messageId: Int32,
        globallyUniqueId: Int64?,
        senderPeerId: Int64?,
        timestampMs: Int64,
        text: String
    ) {
        self.chatPeerId = chatPeerId
        self.messageNamespace = messageNamespace
        self.messageId = messageId
        self.globallyUniqueId = globallyUniqueId
        self.senderPeerId = senderPeerId
        self.timestampMs = timestampMs
        self.text = text
    }
}

public struct JerkgramMessageGuardEntry {
    public let chatPeerId: Int64
    public let messageNamespace: Int32
    public let messageId: Int32
    public let globallyUniqueId: Int64?
    public let senderPeerId: Int64?
    public let timestampMs: Int64
    public let text: String
}

public enum JerkgramMessageGuard {
    private struct Key: Hashable {
        let chatPeerId: Int64
        let messageNamespace: Int32
        let messageId: Int32
    }

    private struct AccountState {
        var entries: [Key: JerkgramMessageGuardEntry] = [:]
        var globalIds: [Int64: Key] = [:]
        var chatQueues: [Int64: [Key]] = [:]
        // Insertion order of the account, kept as a ring so that eviction stays
        // amortised constant instead of shifting the whole array per message.
        var globalQueue: [Key] = []
        var globalQueueStart: Int = 0
        var order: Int64 = 0
    }

    private static let lock = NSLock()
    private static var states: [Int64: AccountState] = [:]

    private static let maximumMessagesPerChat = 300
    private static let maximumMessagesPerAccount = 8_000
    private static let maximumTextLength = 512

    public static func note(accountPeerId: Int64, notes: [JerkgramIncomingMessageNote]) {
        guard !notes.isEmpty else { return }
        self.lock.lock()
        defer { self.lock.unlock() }

        var state = self.states[accountPeerId] ?? AccountState()
        for note in notes {
            let text = note.text
            if text.isEmpty {
                continue
            }
            let key = Key(
                chatPeerId: note.chatPeerId,
                messageNamespace: note.messageNamespace,
                messageId: note.messageId
            )
            if state.entries[key] == nil {
                state.chatQueues[note.chatPeerId, default: []].append(key)
                state.globalQueue.append(key)
            }
            state.order += 1
            state.entries[key] = JerkgramMessageGuardEntry(
                chatPeerId: note.chatPeerId,
                messageNamespace: note.messageNamespace,
                messageId: note.messageId,
                globallyUniqueId: note.globallyUniqueId,
                senderPeerId: note.senderPeerId,
                timestampMs: note.timestampMs,
                text: text.count > self.maximumTextLength
                    ? String(text.prefix(self.maximumTextLength))
                    : text
            )
            if let globallyUniqueId = note.globallyUniqueId {
                state.globalIds[globallyUniqueId] = key
            }
            self.enforceCapacity(state: &state, chatPeerId: note.chatPeerId)
        }
        self.states[accountPeerId] = state
    }

    public static func text(
        accountPeerId: Int64,
        chatPeerId: Int64,
        messageNamespace: Int32,
        messageId: Int32
    ) -> String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        let key = Key(
            chatPeerId: chatPeerId,
            messageNamespace: messageNamespace,
            messageId: messageId
        )
        return self.states[accountPeerId]?.entries[key]?.text
    }

    public static func entry(
        accountPeerId: Int64,
        globallyUniqueId: Int64
    ) -> JerkgramMessageGuardEntry? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let state = self.states[accountPeerId],
              let key = state.globalIds[globallyUniqueId] else {
            return nil
        }
        return state.entries[key]
    }

    public static func count(accountPeerId: Int64) -> Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.states[accountPeerId]?.entries.count ?? 0
    }

    public static func reset(accountPeerId: Int64?) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let accountPeerId = accountPeerId {
            self.states.removeValue(forKey: accountPeerId)
        } else {
            self.states.removeAll()
        }
    }

    private static func enforceCapacity(state: inout AccountState, chatPeerId: Int64) {
        while let queue = state.chatQueues[chatPeerId], queue.count > self.maximumMessagesPerChat {
            let key = queue[0]
            state.chatQueues[chatPeerId]?.removeFirst()
            state.entries.removeValue(forKey: key)
        }
        while state.globalQueue.count - state.globalQueueStart > self.maximumMessagesPerAccount {
            let key = state.globalQueue[state.globalQueueStart]
            state.globalQueueStart += 1
            state.chatQueues[key.chatPeerId]?.removeAll(where: { $0 == key })
            if let entry = state.entries[key], let globallyUniqueId = entry.globallyUniqueId {
                if state.globalIds[globallyUniqueId] == key {
                    state.globalIds.removeValue(forKey: globallyUniqueId)
                }
            }
            state.entries.removeValue(forKey: key)
        }
        if state.globalQueueStart > 4_096 && state.globalQueueStart * 2 > state.globalQueue.count {
            state.globalQueue.removeFirst(state.globalQueueStart)
            state.globalQueueStart = 0
        }
    }
}
