import Foundation
import Darwin

public enum SharedStoreError: Error, LocalizedError {
    case unavailableContainer
    case lockFailed(Int32)
    case invalidPendingState

    public var errorDescription: String? {
        switch self {
        case .unavailableContainer: return "Shared storage is unavailable. Verify the App Group entitlement on both targets."
        case .lockFailed: return "Shared state is busy or unavailable. Try again."
        case .invalidPendingState: return "The pending receive state could not be restored. Reopen the original message."
        }
    }
}

/// An OS advisory lock, shared by the app and extension. Awaited work may hold the lock;
/// waiting for acquisition runs on a utility queue and never blocks the main actor.
/// Acquisition stops after at most ten seconds if another process is suspended while holding it.
public struct FileLock: Sendable {
    public let url: URL
    private let timeout: TimeInterval
    public init(url: URL, timeout: TimeInterval = 10) {
        self.url = url
        self.timeout = timeout.isFinite ? min(max(timeout, 0), 10) : 10
    }

    public func withLock<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        let descriptor: Int32 = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
                guard descriptor >= 0 else {
                    continuation.resume(throwing: SharedStoreError.lockFailed(errno)); return
                }
                let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
                while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
                    let code = errno
                    guard code == EWOULDBLOCK || code == EAGAIN || code == EINTR else {
                        Darwin.close(descriptor)
                        continuation.resume(throwing: SharedStoreError.lockFailed(code)); return
                    }
                    guard DispatchTime.now().uptimeNanoseconds < deadline else {
                        Darwin.close(descriptor)
                        continuation.resume(throwing: SharedStoreError.lockFailed(ETIMEDOUT)); return
                    }
                    Thread.sleep(forTimeInterval: 0.025)
                }
                continuation.resume(returning: descriptor)
            }
        }
        defer {
            flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
        }
        try Task.checkCancellation()
        return try await operation()
    }
}
