import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Thread-safe manager handling data persistence and image files across the
/// App Group sandbox boundary between HeirLoom and HeirLoomShareExtension.
public final class AppGroupStorage: @unchecked Sendable {
    public static let shared = AppGroupStorage()
    public static let appGroupIdentifier = "group.com.heirloom.app"
    private static let queueKey = "heirloom.pending_shared_posts"

    private let userDefaults: UserDefaults?
    private let sharedDirectoryURL: URL?
    private let lock = NSLock()

    public init() {
        self.userDefaults = UserDefaults(suiteName: Self.appGroupIdentifier)
        self.sharedDirectoryURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)?
            .appendingPathComponent("shared_posts", isDirectory: true)

        if let dir = sharedDirectoryURL, !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Saves a newly shared post and its binary image data to the shared container.
    public func savePendingPost(payload: SharedPostPayload, imageData: Data?) throws {
        lock.lock()
        defer { lock.unlock() }

        var updatedPayload = payload
        if let data = imageData, let dir = sharedDirectoryURL {
            let filename = "\(payload.id).jpg"
            let fileURL = dir.appendingPathComponent(filename)
            try data.write(to: fileURL, options: .atomic)
            updatedPayload = SharedPostPayload(
                id: payload.id,
                source: payload.source,
                caption: payload.caption,
                postURL: payload.postURL,
                imageFileName: filename,
                authorId: payload.authorId,
                authorName: payload.authorName,
                timestamp: payload.timestamp,
                status: .pending
            )
        }

        var current = fetchPendingPostsLocked()
        current.removeAll { $0.id == updatedPayload.id }
        current.append(updatedPayload)
        saveQueueLocked(current)
    }

    /// Fetches all pending shared posts awaiting ingestion by the main app.
    public func fetchPendingPosts() -> [SharedPostPayload] {
        lock.lock()
        defer { lock.unlock() }
        return fetchPendingPostsLocked()
    }

    /// Reads binary image data from the shared container filesystem.
    public func loadImageData(for payload: SharedPostPayload) -> Data? {
        guard let filename = payload.imageFileName, let dir = sharedDirectoryURL else { return nil }
        let fileURL = dir.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }

    /// Loads image data from a relative image file name.
    public func loadImageData(named filename: String) -> Data? {
        guard let dir = sharedDirectoryURL else { return nil }
        let fileURL = dir.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }

    /// Saves a UIImage / Data into the shared folder, returning the relative filename.
    public func saveSharedImage(data: Data, prefix: String = "in_app") -> String? {
        guard let dir = sharedDirectoryURL else { return nil }
        let filename = "\(prefix)_\(UUID().uuidString).jpg"
        let fileURL = dir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL, options: .atomic)
            return filename
        } catch {
            print("[AppGroupStorage] Failed to save shared image: \(error.localizedDescription)")
            return nil
        }
    }

    /// Marks a post as ingested and removes it from the pending queue.
    public func markPostCompleted(id: String) {
        lock.lock()
        defer { lock.unlock() }
        var current = fetchPendingPostsLocked()
        if let index = current.firstIndex(where: { $0.id == id }) {
            current.remove(at: index)
            saveQueueLocked(current)
        }
    }

    // MARK: - Internal Helpers

    private func fetchPendingPostsLocked() -> [SharedPostPayload] {
        guard let data = userDefaults?.data(forKey: Self.queueKey),
              let list = try? JSONDecoder().decode([SharedPostPayload].self, from: data)
        else { return [] }
        return list
    }

    private func saveQueueLocked(_ queue: [SharedPostPayload]) {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        userDefaults?.set(data, forKey: Self.queueKey)
        userDefaults?.synchronize()
    }
}
