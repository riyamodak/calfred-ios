import CalendarDomain
import Foundation

/// Stores just the M0 setup handoff. This is not an import journal or a receipt store.
/// Credentials belong exclusively in the shared Keychain.
public struct PendingReceiveStore: Sendable {
    private let fileURL: URL
    private let fileLock: FileLock

    public init(containerURL: URL) throws {
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        fileURL = containerURL.appendingPathComponent("m0-pending-receive.json")
        fileLock = FileLock(url: containerURL.appendingPathComponent("m0-pending-receive.lock"))
    }

    public static func appGroup(_ identifier: String) throws -> PendingReceiveStore {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw SharedStoreError.unavailableContainer
        }
        return try PendingReceiveStore(containerURL: url)
    }

    public func load() async throws -> ReceiveDraft? {
        try await fileLock.withLock { try loadLocked() }
    }

    public func save(_ draft: ReceiveDraft) async throws {
        try await fileLock.withLock { try saveLocked(draft) }
    }

    /// Read, change, and replace the current pending state under a single cross-process lock.
    /// An absent draft stays absent; connection changes must never invent a receive operation.
    public func update(_ transform: @Sendable (inout ReceiveDraft) -> Void) async throws {
        try await fileLock.withLock {
            guard var draft = try loadLocked() else { return }
            transform(&draft)
            try saveLocked(draft)
        }
    }

    public func clear() async throws {
        try await fileLock.withLock {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func loadLocked() throws -> ReceiveDraft? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            guard data.count <= 32_768 else { throw SharedStoreError.invalidPendingState }
            return try JSONDecoder().decode(ReceiveDraft.self, from: data)
        } catch {
            throw SharedStoreError.invalidPendingState
        }
    }

    private func saveLocked(_ draft: ReceiveDraft) throws {
        try draft.effectiveEvent.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(draft)
        guard data.count <= 32_768 else { throw SharedStoreError.invalidPendingState }
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        var resourceURL = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
    }
}
