import CalendarDomain
import Darwin
import Foundation
import MessageCodec
import SharedStore
import XCTest

final class PendingReceiveStoreTests: XCTestCase {
    func testNewReceiveHasNoDestinationAndNoWrite() {
        let draft = ReceiveDraft(snapshot: M0Samples.allDaySnapshot())
        XCTAssertNil(draft.selectedDestination)
        XCTAssertFalse(draft.writeAttempted)
        XCTAssertNil(draft.writeResult)
    }

    func testPendingDraftPreservesEditsDestinationAndAttemptAcrossInstances() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try PendingReceiveStore(containerURL: folder)
        var draft = ReceiveDraft(snapshot: M0Samples.allDaySnapshot())
        draft.title = "My edited trip 🧳"
        draft.location = "Montréal"
        draft.note = "Keep this local edit"
        draft.selectedDestination = googleDestination(account: "account-a")
        draft.writeAttempted = true
        draft.writeResult = "Check the calendar after an uncertain attempt."
        try await first.save(draft)

        let coldInstance = try PendingReceiveStore(containerURL: folder)
        let restored = try await coldInstance.load()
        XCTAssertEqual(restored, draft)
        XCTAssertEqual(restored?.snapshot.event.title, "Trip to Chicago")
        XCTAssertEqual(restored?.effectiveEvent.title, "My edited trip 🧳")
        XCTAssertTrue(restored?.writeAttempted == true)
        try await coldInstance.clear()
        let cleared = try await first.load()
        XCTAssertNil(cleared)
    }

    func testAccountSwitchClearsOnlyOldGoogleDestinationAndPreservesEdits() {
        var draft = ReceiveDraft(snapshot: M0Samples.allDaySnapshot(), selectedDestination: googleDestination(account: "account-a"))
        draft.title = "Keep my edit"
        draft.invalidateGoogleDestination(unlessAccountKey: "account-a")
        XCTAssertNotNil(draft.selectedDestination, "A canceled same-account upgrade keeps a still-valid choice")
        draft.invalidateGoogleDestination(unlessAccountKey: "account-b")
        XCTAssertNil(draft.selectedDestination)
        XCTAssertEqual(draft.title, "Keep my edit")
        draft.selectedDestination = CalendarRef(provider: .apple, accountKey: "device", calendarID: "apple-cal",
                                               displayName: "Local", accountLabel: "On this iPhone", isWritable: true)
        draft.invalidateGoogleDestination(unlessAccountKey: nil)
        XCTAssertEqual(draft.selectedDestination?.provider, .apple)
    }

    func testCorruptStateReturnsRecoverableError() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try PendingReceiveStore(containerURL: folder)
        try Data("not JSON".utf8).write(to: folder.appendingPathComponent("m0-pending-receive.json"))
        do {
            _ = try await store.load()
            XCTFail("Expected an invalid pending-state error")
        } catch {
            XCTAssertTrue(error is SharedStoreError)
        }
    }

    func testAtomicUpdatesRetainConcurrentChangesToDistinctFields() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try PendingReceiveStore(containerURL: folder)
        let second = try PendingReceiveStore(containerURL: folder)
        let original = ReceiveDraft(snapshot: M0Samples.allDaySnapshot())
        try await first.save(original)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask { try await first.update { $0.title += "T" } }
                group.addTask { try await second.update { $0.note += "N" } }
            }
            try await group.waitForAll()
        }
        let loaded = try await first.load()
        let restored = try XCTUnwrap(loaded)
        XCTAssertEqual(restored.title, original.title + String(repeating: "T", count: 12))
        XCTAssertEqual(restored.note, String(repeating: "N", count: 12))
        XCTAssertEqual(restored.snapshot, original.snapshot)
        XCTAssertNil(restored.selectedDestination)
        XCTAssertFalse(restored.writeAttempted)
    }

    func testUpdatingMissingDraftDoesNotCreateReceiveState() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try PendingReceiveStore(containerURL: folder)
        try await store.update { $0.title = "Should not be created" }
        let loaded = try await store.load()
        XCTAssertNil(loaded)
    }

    func testLockContentionHasRecoverableTimeout() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lockURL = folder.appendingPathComponent("held.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        let started = Date()
        do {
            try await FileLock(url: lockURL, timeout: 0.05).withLock {
                XCTFail("Contended lock must not execute its operation")
            }
            XCTFail("Expected bounded lock acquisition to fail")
        } catch SharedStoreError.lockFailed(let code) {
            XCTAssertEqual(code, ETIMEDOUT)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testSeparateFileLockInstancesSerializeReadModifyWrite() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("counter")
        let lockURL = folder.appendingPathComponent("counter.lock")
        try Data("0".utf8).write(to: file)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await FileLock(url: lockURL).withLock {
                        let old = Int(String(decoding: try Data(contentsOf: file), as: UTF8.self))!
                        await Task.yield()
                        try Data(String(old + 1).utf8).write(to: file, options: .atomic)
                    }
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(String(decoding: try Data(contentsOf: file), as: UTF8.self), "20")
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CalendarShareTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func googleDestination(account: String) -> CalendarRef {
        CalendarRef(provider: .google, accountKey: account, calendarID: "destination", displayName: "Travel",
                    accountLabel: "Direct Google", isWritable: true)
    }
}
