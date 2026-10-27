import XCTest
import CryptoKit
import LocalAuthentication
import AppKit
import VaultCore
@testable import Stillwater

private final class CancelledKeychain: BiometricKeyStore {
    func save(_ key: SymmetricKey, id: UUID) throws {}
    func load(id: UUID, context: LAContext) throws -> SymmetricKey { throw KeychainError.cancelled }
    func remove(id: UUID) throws {}
}
private final class MemoryKeychain: BiometricKeyStore {
    var key: SymmetricKey?
    var cancelled = false
    func save(_ key: SymmetricKey, id: UUID) throws { self.key = key }
    func load(id: UUID, context: LAContext) throws -> SymmetricKey {
        guard !cancelled, let key else { throw KeychainError.cancelled }
        return key
    }
    func remove(id: UUID) throws { key = nil }
}
@MainActor final class SessionTests: XCTestCase {
    func testTouchIDCancellationLeavesVaultLockedAndMasterPasswordWorks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = VaultSession(keychain: CancelledKeychain(), url: directory.appendingPathComponent("vault"), monitor: false)
        await session.create(password: "Fictional garden lantern 942!")
        XCTAssertTrue(session.unlocked)
        session.lock(); XCTAssertNil(session.payload)
        await session.unlockWithTouchID(); XCTAssertFalse(session.unlocked); XCTAssertFalse(session.busy)
        session.message = nil
        await session.unlock(password: "Fictional garden lantern 942!"); XCTAssertTrue(session.unlocked)
        session.timeoutMinutes = 0; session.checkIdle(); XCTAssertFalse(session.unlocked)
    }
    func testRestoreRejectsInvalidBackupAndWorksWithoutOriginalKeychain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("vault")
        let session = VaultSession(keychain: CancelledKeychain(), url: location, monitor: false)
        await session.create(password: "Fictional existing garden 748!")
        let original = try VaultFile(url: location).read()
        var payload = VaultPayload(); var account = Account()
        account.name = "Restored Fictional Mail"; account.password = "fictional account secret"
        payload.accounts = [account]
        let (backup, _) = try VaultCrypto.create(password: "Fictional backup river 258!", payload: payload)
        let backupURL = directory.appendingPathComponent("backup")
        try VaultFile(url: backupURL).write(backup.encoded(), expected: nil)
        await session.restore(from: backupURL, password: "wrong password")
        XCTAssertEqual(try VaultFile(url: location).read(), original)
        session.message = nil
        await session.restore(from: backupURL, password: "Fictional backup river 258!")
        XCTAssertEqual(session.payload, payload)
        XCTAssertFalse(session.biometricEnabled)
        session.lock()
        await session.unlock(password: "Fictional backup river 258!")
        XCTAssertEqual(session.payload, payload)
    }
    func testEnrolledVaultRequiresTouchIDWithExplicitPasswordRecoveryAfterRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault")
        let store = MemoryKeychain()
        let password = "Fictional garden lantern 942!"
        let session = VaultSession(keychain: store, url: url, monitor: false)
        await session.create(password: password)
        let id = try VaultEnvelope.decode(VaultFile(url: url).read()).header.id
        defer { UserDefaults.standard.removeObject(forKey: "touchID.\(id)") }
        await session.setBiometrics(true, password: password)
        XCTAssertTrue(session.biometricEnabled)
        session.lock()
        let restarted = VaultSession(keychain: store, url: url, monitor: false)
        XCTAssertTrue(restarted.biometricEnabled)
        await restarted.unlock(password: password)
        XCTAssertFalse(restarted.unlocked)
        XCTAssertFalse(restarted.busy)
        store.cancelled = true
        await restarted.unlockWithTouchID()
        XCTAssertFalse(restarted.unlocked)
        await restarted.unlock(password: "wrong password", recovery: true)
        XCTAssertFalse(restarted.unlocked)
        await restarted.unlock(password: password, recovery: true)
        XCTAssertTrue(restarted.unlocked)
        XCTAssertTrue(restarted.biometricEnabled)
        restarted.lock()
        store.cancelled = false
        await restarted.unlockWithTouchID()
        XCTAssertTrue(restarted.unlocked)
    }
    func testClipboardDoesNotEraseLaterCopy() {
        let clipboard = SensitiveClipboard()
        clipboard.copy("fictional secret")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("later user copy", forType: .string)
        clipboard.clear()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "later user copy")
        clipboard.copy("another fictional secret"); clipboard.clear()
        XCTAssertNil(NSPasteboard.general.string(forType: .string))
    }
}
