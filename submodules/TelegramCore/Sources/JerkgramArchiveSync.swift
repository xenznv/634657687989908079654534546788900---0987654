import Foundation
import Postbox
import JerkgramCore
import SwiftSignalKit

// Pulls deleted messages from the external archive API (see JerkgramCore)
// and restores them into the local message store as regular "deleted" messages,
// exactly like deletions observed live: the text survives, the bubble keeps its
// deleted mark, and the message stays in the chat.
//
// Saved media comes along: files are downloaded into the app's cache and turned
// into real Telegram media (see JerkgramArchiveMedia), so a restored photo is a
// photo bubble and a restored video plays, instead of the message being text-only.

// A restore runs while a chat is opening, so it will not pull arbitrarily large
// video files; anything bigger keeps the text and is reported to the log.
private let jerkgramArchiveMaxMediaBytes: Int64 = 25 * 1024 * 1024

// Media that could not be fetched right now (network, timeout): the sync mark
// stays put so the next chat open tries again. Files that can never be used
// (too large, unreadable) are not listed here, so they do not cause churn.
private struct JerkgramArchiveMediaResult {
    let mediaByMessageId: [Int32: Media]
    let retryableMessageIds: Set<Int32>
}

public func jerkgramSyncArchivedMessages(
    accountPeerId: PeerId,
    peerId: PeerId,
    postbox: Postbox,
    completion: @escaping (Int) -> Void
) {
    guard let client = JerkgramArchiveClient.fromSettings() else {
        JerkgramDebugConsole.error("archive sync: client not configured")
        completion(0)
        return
    }

    // The archive API speaks raw Telegram ids, not packed PeerId values:
    // user ids no longer fitting 32 bits arrive distorted via toInt64(),
    // so the id is taken from the PeerId itself (namespace-free).
    let accountId = accountPeerId.id._internalGetInt64Value()
    let chatId = peerId.id._internalGetInt64Value()
    let after = JerkgramArchiveSettings.lastSync(accountPeerId: accountId, chatPeerId: chatId)
    JerkgramDebugConsole.log(
        "archive sync: chat=\(chatId) after=\(after)"
    )

    client.fetchUpdates(chatId: chatId, after: after) { updates in
        guard let updates = updates else {
            JerkgramDebugConsole.error(
                "archive sync: no response for chat=\(chatId)"
            )
            completion(0)
            return
        }

        guard !updates.deleted.isEmpty else {
            JerkgramDebugConsole.log(
                "archive sync: chat=\(chatId) has no deleted messages"
            )
            JerkgramArchiveSettings.setLastSync(
                accountPeerId: accountId,
                chatPeerId: chatId,
                value: updates.serverTime
            )
            completion(0)
            return
        }

        JerkgramDebugConsole.log(
            "archive sync: chat=\(chatId) restoring \(updates.deleted.count) message(s)"
        )

        jerkgramDownloadArchivedMedia(
            client: client,
            chatId: chatId,
            items: updates.deleted
        ) { mediaResult in
            let mediaByMessageId = mediaResult.mediaByMessageId
            let _ = (postbox.transaction { transaction -> Int in
                var changed = 0

                for item in updates.deleted {
                    let messageId = MessageId(
                        peerId: peerId,
                        namespace: Namespaces.Message.Cloud,
                        id: item.messageId
                    )
                    let timestamp = Int32(
                        (item.date ?? Date()).timeIntervalSince1970
                    )
                    let deletedAt = Int32(
                        (item.deletedAt ?? item.date ?? Date()).timeIntervalSince1970
                    )
                    let text = item.text ?? ""
                    let archivedMedia = mediaByMessageId[item.messageId]

                    if let existing = transaction.getMessage(messageId) {
                        // The message is already local (arrived before deletion):
                        // make sure it carries the deleted mark, and give it the
                        // archived file when the device never kept one.
                        let ghost = existing.attributes.first(
                            where: { $0 is GhostBaseMessageAttribute }
                        ) as? GhostBaseMessageAttribute

                        var attributes = existing.attributes
                        var needsUpdate = false

                        if ghost?.isDeleted != true {
                            attributes.removeAll(where: { $0 is GhostBaseMessageAttribute })
                            attributes.append(GhostBaseMessageAttribute(
                                originalText: ghost?.originalText
                                    ?? (existing.text.isEmpty ? nil : existing.text),
                                editHistoryTexts: ghost?.editHistoryTexts ?? [],
                                editHistoryDates: ghost?.editHistoryDates ?? [],
                                isDeleted: true,
                                deletedAt: deletedAt,
                                originalEntities: ghost?.originalEntities ?? []
                            ))
                            needsUpdate = true
                        }

                        var media = existing.media
                        if media.isEmpty, let archivedMedia = archivedMedia {
                            media = [archivedMedia]
                            needsUpdate = true
                        }

                        if needsUpdate {
                            transaction.updateMessage(messageId, update: { current in
                                return .update(StoreMessage(
                                    id: current.id,
                                    customStableId: nil,
                                    globallyUniqueId: current.globallyUniqueId,
                                    groupingKey: current.groupingKey,
                                    threadId: current.threadId,
                                    timestamp: current.timestamp,
                                    flags: StoreMessageFlags(current.flags),
                                    tags: current.tags,
                                    globalTags: current.globalTags,
                                    localTags: current.localTags,
                                    forwardInfo: current.forwardInfo.flatMap(StoreMessageForwardInfo.init),
                                    authorId: current.author?.id,
                                    text: current.text,
                                    attributes: attributes,
                                    media: media
                                ))
                            })
                            changed += 1
                        }
                    } else {
                        // The message never reached this device: recreate it from
                        // the archive with the text, the media and the deleted mark.
                        let incoming = item.direction != "outgoing"
                        var storeFlags = StoreMessageFlags()
                        if incoming {
                            storeFlags.insert(.Incoming)
                        }

                        let media: [Media] = archivedMedia.map { [$0] } ?? []
                        let attributes: [MessageAttribute] = [
                            GhostBaseMessageAttribute(
                                originalText: text.isEmpty ? nil : text,
                                editHistoryTexts: [],
                                editHistoryDates: [],
                                isDeleted: true,
                                deletedAt: deletedAt
                            )
                        ]
                        let (tags, globalTags) = tagsForStoreMessage(
                            incoming: incoming,
                            attributes: attributes,
                            media: media,
                            textEntities: nil,
                            isPinned: false
                        )

                        let storeMessage = StoreMessage(
                            id: messageId,
                            customStableId: nil,
                            globallyUniqueId: nil,
                            groupingKey: nil,
                            threadId: nil,
                            timestamp: timestamp,
                            flags: storeFlags,
                            tags: tags,
                            globalTags: globalTags,
                            localTags: LocalMessageTags(),
                            forwardInfo: nil,
                            authorId: item.senderId.map { PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value($0)) },
                            text: text,
                            attributes: attributes,
                            media: media
                        )
                        let _ = transaction.addMessages([storeMessage], location: .Random)
                        changed += 1
                    }
                }

                return changed
            } |> deliverOnMainQueue).start(next: { changed in
                JerkgramDebugConsole.log(
                    "archive sync: chat=\(chatId) restored \(changed) message(s)"
                )
                if mediaResult.retryableMessageIds.isEmpty {
                    JerkgramArchiveSettings.setLastSync(
                        accountPeerId: accountId,
                        chatPeerId: chatId,
                        value: updates.serverTime
                    )
                } else {
                    JerkgramDebugConsole.log(
                        "archive sync will retry media for \(mediaResult.retryableMessageIds.count) message(s)"
                    )
                }
                completion(changed)
            })
        }
    }
}

// Downloads the media of the given archive items one after another (the numbers
// here are small) and returns the ready media objects keyed by message id. Every
// failure is only logged: a message without its file is still worth restoring.
private func jerkgramDownloadArchivedMedia(
    client: JerkgramArchiveClient,
    chatId: Int64,
    items: [JerkgramArchiveDeletedMessage],
    completion: @escaping (JerkgramArchiveMediaResult) -> Void
) {
    var pending = items.filter { item in
        guard let path = item.mediaPath else {
            return false
        }
        return !path.isEmpty
    }
    var mediaByMessageId: [Int32: Media] = [:]
    var retryableMessageIds: Set<Int32> = []

    func step() {
        guard !pending.isEmpty else {
            completion(JerkgramArchiveMediaResult(
                mediaByMessageId: mediaByMessageId,
                retryableMessageIds: retryableMessageIds
            ))
            return
        }
        let item = pending.removeFirst()
        guard let relativePath = item.mediaPath, !relativePath.isEmpty else {
            step()
            return
        }
        if let expectedSize = item.mediaSize, expectedSize > jerkgramArchiveMaxMediaBytes {
            JerkgramDebugConsole.log(
                "archive media skipped id=\(item.messageId) bytes=\(expectedSize)"
            )
            step()
            return
        }

        let localFile = jerkgramArchiveMediaLocalFile(
            chatId: chatId,
            messageId: item.messageId,
            mediaType: item.mediaType,
            relativePath: relativePath
        )

        let cachedSize = jerkgramArchiveFileSize(localFile)
        if cachedSize > 0 {
            if let media = jerkgramArchiveMediaObject(
                mediaType: item.mediaType,
                relativePath: relativePath,
                localFile: localFile,
                byteSize: cachedSize
            ) {
                mediaByMessageId[item.messageId] = media
            } else {
                JerkgramDebugConsole.log(
                    "archive media unreadable id=\(item.messageId) type=\(item.mediaType ?? "?")"
                )
            }
            step()
            return
        }

        client.downloadMedia(relativePath: relativePath, destination: localFile) { result in
            switch result {
            case let .success(byteSize):
                // The size is also checked after the fact: older builds of the
                // archive API do not report it before the download.
                if byteSize > jerkgramArchiveMaxMediaBytes {
                    try? FileManager.default.removeItem(at: localFile)
                    JerkgramDebugConsole.log(
                        "archive media skipped after download id=\(item.messageId) bytes=\(byteSize)"
                    )
                    step()
                    return
                }
                if let media = jerkgramArchiveMediaObject(
                    mediaType: item.mediaType,
                    relativePath: relativePath,
                    localFile: localFile,
                    byteSize: byteSize
                ) {
                    mediaByMessageId[item.messageId] = media
                    JerkgramDebugConsole.log(
                        "archive media restored id=\(item.messageId) type=\(item.mediaType ?? "?") bytes=\(byteSize)"
                    )
                } else {
                    JerkgramDebugConsole.log(
                        "archive media unreadable id=\(item.messageId) type=\(item.mediaType ?? "?")"
                    )
                }
            case .failure(let error):
                retryableMessageIds.insert(item.messageId)
                JerkgramDebugConsole.log(
                    "archive media failed id=\(item.messageId): \(error)"
                )
            }
            step()
        }
    }

    step()
}
