import Foundation
import BuildConfig

// Client for the external archive API served by the message saver bot.
// Read-only: lists deleted/edited messages that the
// Telegram server no longer returns, so the fork can restore them locally.

public enum JerkgramArchiveSettingsKey {
    public static let serverURL = "jerkgram.Archive.ServerURL"
    public static let token = "jerkgram.Archive.Token"
    public static let status = "jerkgram.Archive.Status"
    public static let lastSyncPrefix = "jerkgram.Archive.LastSync."
}

public final class JerkgramArchiveSettings {
    // The archive is wired into the build by default (URL and token come from
    // build-time configuration); UserDefaults only ever overrides it.
    public static var serverURL: String {
        get {
            let stored = (UserDefaults.standard.string(forKey: JerkgramArchiveSettingsKey.serverURL) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stored.isEmpty {
                return stored
            }
            return BuildConfig.jerkgramArchiveURL()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: JerkgramArchiveSettingsKey.serverURL
            )
        }
    }

    public static var token: String {
        get {
            let stored = (UserDefaults.standard.string(forKey: JerkgramArchiveSettingsKey.token) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stored.isEmpty {
                return stored
            }
            return BuildConfig.jerkgramArchiveToken()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: JerkgramArchiveSettingsKey.token
            )
        }
    }

    public static var isConfigured: Bool {
        return !self.serverURL.isEmpty && !self.token.isEmpty
    }

    public static var status: String {
        get {
            return UserDefaults.standard.string(forKey: JerkgramArchiveSettingsKey.status) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: JerkgramArchiveSettingsKey.status)
        }
    }

    private static func lastSyncKey(accountPeerId: Int64, chatPeerId: Int64) -> String {
        return JerkgramArchiveSettingsKey.lastSyncPrefix
            + "\(accountPeerId).\(chatPeerId)"
    }

    public static func lastSync(accountPeerId: Int64, chatPeerId: Int64) -> Int {
        return UserDefaults.standard.integer(
            forKey: self.lastSyncKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
        )
    }

    public static func setLastSync(accountPeerId: Int64, chatPeerId: Int64, value: Int) {
        UserDefaults.standard.set(
            value,
            forKey: self.lastSyncKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
        )
    }
}

public struct JerkgramArchiveDeletedMessage {
    public let messageId: Int32
    public let senderId: Int64?
    public let senderName: String?
    public let date: Date?
    public let deletedAt: Date?
    public let text: String?
    public let direction: String?
    // Saved media: "photo", "video", "voice", "document"... plus the path
    // relative to the archive's media root, usable in a /media/ request.
    public let mediaType: String?
    public let mediaPath: String?
    public let mediaSize: Int64?

    public init(
        messageId: Int32,
        senderId: Int64?,
        senderName: String?,
        date: Date?,
        deletedAt: Date?,
        text: String?,
        direction: String?,
        mediaType: String? = nil,
        mediaPath: String? = nil,
        mediaSize: Int64? = nil
    ) {
        self.messageId = messageId
        self.senderId = senderId
        self.senderName = senderName
        self.date = date
        self.deletedAt = deletedAt
        self.text = text
        self.direction = direction
        self.mediaType = mediaType
        self.mediaPath = mediaPath
        self.mediaSize = mediaSize
    }
}

public struct JerkgramArchiveUpdates {
    public let serverTime: Int
    public let deleted: [JerkgramArchiveDeletedMessage]

    public init(serverTime: Int, deleted: [JerkgramArchiveDeletedMessage]) {
        self.serverTime = serverTime
        self.deleted = deleted
    }
}

public enum JerkgramArchiveClientError: Error {
    case badURL
    case unauthorized
    case http(Int)
    case decoding
}

public final class JerkgramArchiveClient {
    private let baseURL: URL
    private let token: String
    private let session: URLSession
    // Media downloads are plain file transfers: they need a much longer budget
    // than the small JSON calls handled by `session`.
    private let mediaSession: URLSession

    public init?(serverURL: String, token: String) {
        var trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        self.baseURL = url
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20.0
        configuration.timeoutIntervalForResource = 40.0
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)

        let mediaConfiguration = URLSessionConfiguration.ephemeral
        mediaConfiguration.timeoutIntervalForRequest = 60.0
        mediaConfiguration.timeoutIntervalForResource = 300.0
        mediaConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.mediaSession = URLSession(configuration: mediaConfiguration)
    }

    public static func fromSettings() -> JerkgramArchiveClient? {
        guard JerkgramArchiveSettings.isConfigured else {
            return nil
        }
        return JerkgramArchiveClient(
            serverURL: JerkgramArchiveSettings.serverURL,
            token: JerkgramArchiveSettings.token
        )
    }

    private func request(path: String, query: [URLQueryItem]) -> URLRequest? {
        guard var components = URLComponents(
            url: self.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        var items = query
        items.append(URLQueryItem(name: "token", value: self.token))
        components.queryItems = items
        guard let url = components.url else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(self.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func run(
        _ request: URLRequest,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let task = self.session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(JerkgramArchiveClientError.decoding))
                return
            }
            if http.statusCode == 401 {
                completion(.failure(JerkgramArchiveClientError.unauthorized))
                return
            }
            guard (200 ..< 300).contains(http.statusCode), let data = data else {
                completion(.failure(JerkgramArchiveClientError.http(http.statusCode)))
                return
            }
            completion(.success(data))
        }
        task.resume()
    }

    /// Absolute URL of one saved media file inside the archive API.
    public func mediaURL(relativePath: String) -> URL? {
        return self.request(path: "media/\(relativePath)", query: [])?.url
    }

    /// Downloads one archived media file (photo, video, document) into `destination`.
    ///
    /// `relativePath` is the `media_path` reported by the API; the token travels in
    /// the query string as well, so the file can also be fetched without headers.
    public func downloadMedia(
        relativePath: String,
        destination: URL,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        guard let url = self.mediaURL(relativePath: relativePath) else {
            completion(.failure(JerkgramArchiveClientError.badURL))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(self.token)", forHTTPHeaderField: "Authorization")
        let task = self.mediaSession.downloadTask(with: request) { location, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(JerkgramArchiveClientError.decoding))
                return
            }
            if http.statusCode == 401 {
                completion(.failure(JerkgramArchiveClientError.unauthorized))
                return
            }
            guard (200 ..< 300).contains(http.statusCode), let location = location else {
                completion(.failure(JerkgramArchiveClientError.http(http.statusCode)))
                return
            }
            do {
                let fileManager = FileManager.default
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: location, to: destination)
                let attributes = try fileManager.attributesOfItem(atPath: destination.path)
                let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                completion(.success(fileSize))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    public func fetchMessageCount(completion: @escaping (Result<Int, Error>) -> Void) {
        guard let request = self.request(path: "health", query: []) else {
            completion(.failure(JerkgramArchiveClientError.badURL))
            return
        }
        self.run(request) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let messages = json["messages"] as? Int else {
                    completion(.failure(JerkgramArchiveClientError.decoding))
                    return
                }
                completion(.success(messages))
            }
        }
    }

    public func fetchUpdates(
        chatId: Int64,
        after: Int,
        completion: @escaping (JerkgramArchiveUpdates?) -> Void
    ) {
        guard let request = self.request(
            path: "chat/\(chatId)/updates",
            query: [URLQueryItem(name: "after", value: String(after))]
        ) else {
            completion(nil)
            return
        }
        self.run(request) { result in
            switch result {
            case .failure:
                completion(nil)
            case let .success(data):
                completion(JerkgramArchiveClient.decodeUpdates(data))
            }
        }
    }

    private static func decodeInt64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? NSNumber {
            return value.int64Value
        }
        return nil
    }

    private static func decodeDate(_ value: Any?) -> Date? {
        guard let string = value as? String, !string.isEmpty else {
            return nil
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    private static func decodeUpdates(_ data: Data) -> JerkgramArchiveUpdates? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let serverTime = json["server_time"] as? Int ?? Int(Date().timeIntervalSince1970)
        var deleted: [JerkgramArchiveDeletedMessage] = []
        if let rows = json["deleted"] as? [[String: Any]] {
            for row in rows {
                guard let messageId = row["message_id"] as? Int else {
                    continue
                }
                let senderId: Int64?
                if let value = row["sender_id"] as? Int {
                    senderId = Int64(value)
                } else if let value = row["sender_id"] as? Int64 {
                    senderId = value
                } else {
                    senderId = nil
                }
                deleted.append(
                    JerkgramArchiveDeletedMessage(
                        messageId: Int32(messageId),
                        senderId: senderId,
                        senderName: row["sender_name"] as? String,
                        date: JerkgramArchiveClient.decodeDate(row["date"]),
                        deletedAt: JerkgramArchiveClient.decodeDate(row["deleted_at"]),
                        text: row["text"] as? String,
                        direction: row["direction"] as? String,
                        mediaType: row["media_type"] as? String,
                        mediaPath: row["media_path"] as? String,
                        mediaSize: JerkgramArchiveClient.decodeInt64(row["media_size"])
                    )
                )
            }
        }
        return JerkgramArchiveUpdates(serverTime: serverTime, deleted: deleted)
    }
}
