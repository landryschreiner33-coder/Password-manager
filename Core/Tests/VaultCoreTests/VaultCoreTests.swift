import XCTest
import CryptoKit
@testable import VaultCore

final class VaultCoreTests: XCTestCase {
    let password = "Fictional river stones 482!"
    func fixture() -> VaultPayload {
        var result = VaultPayload(); var account = Account()
        account.name = "Fictional Mail"; account.website = "https://mail.example.invalid"
        account.username = "reader@example.invalid"; account.password = "Fictional-secret-823!"; account.notes = "Private fictional note"
        result.folders = [Folder(name: "Personal")]; account.folderID = result.folders[0].id; result.accounts = [account]
        return result
    }
    func testArgon2idMatchesIndependentReferenceVector() throws {
        let key = try KDFParameters().derive(password: "fictional cross-implementation phrase", salt: Data(0..<16))
        let hex = key.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
        XCTAssertEqual(hex, "f4b6d9e2ab7ae6700a8d1478e8453f6a5297f8bb8956f16cbc5d2a0353559fdf")
    }
    func testRoundTripAndEncryptedMetadata() throws {
        let payload = fixture(); let (envelope, _) = try VaultCrypto.create(password: password, payload: payload)
        let bytes = try envelope.encoded()
        for secret in ["Fictional Mail", "reader@example.invalid", "Personal", "Private fictional note", "Fictional-secret-823!"] {
            XCTAssertNil(bytes.range(of: Data(secret.utf8)))
        }
        let loaded = try VaultEnvelope.decode(bytes)
        XCTAssertEqual(try VaultCrypto.unlock(loaded, password: password).0, payload)
    }
    func testWrongPasswordAndTampering() throws {
        let (envelope, _) = try VaultCrypto.create(password: password, payload: fixture())
        XCTAssertThrowsError(try VaultCrypto.unlock(envelope, password: "definitely incorrect"))
        var tampered = envelope; tampered.ciphertext[tampered.ciphertext.count - 1] ^= 1
        XCTAssertThrowsError(try VaultCrypto.unlock(tampered, password: password))
        tampered = envelope; tampered.wrappedKey[20] ^= 1
        XCTAssertThrowsError(try VaultCrypto.unlock(tampered, password: password))
        tampered = envelope; tampered.header.id = UUID()
        XCTAssertThrowsError(try VaultCrypto.unlock(tampered, password: password))
        let bytes = try envelope.encoded()
        for length in [0, 1, bytes.count / 2, bytes.count - 1] { XCTAssertThrowsError(try VaultEnvelope.decode(bytes.prefix(length))) }
    }
    func testFreshNoncesAndSalt() throws {
        let (first, key) = try VaultCrypto.create(password: password, payload: fixture())
        let next = try VaultCrypto.encrypt(fixture(), key: key, envelope: first)
        XCTAssertNotEqual(first.ciphertext.prefix(12), next.ciphertext.prefix(12))
        let (other, _) = try VaultCrypto.create(password: password)
        XCTAssertNotEqual(first.header.salt, other.header.salt)
    }
    func testPasswordChangeAndPortableBackup() throws {
        let payload = fixture(); let (original, _) = try VaultCrypto.create(password: password, payload: payload)
        let nextPassword = "New fictional mountains 928!"
        let oldKey = try VaultCrypto.unlock(original, password: password).1
        let changed = try VaultCrypto.changePassword(original, oldPassword: password, newPassword: nextPassword)
        XCTAssertThrowsError(try VaultCrypto.decrypt(changed, key: oldKey))
        XCTAssertThrowsError(try VaultCrypto.unlock(changed, password: password))
        // No Keychain dependency is involved in reading this independent serialized copy.
        let restored = try VaultEnvelope.decode(changed.encoded())
        XCTAssertEqual(try VaultCrypto.unlock(restored, password: nextPassword).0, payload)
        XCTAssertEqual(try VaultCrypto.unlock(original, password: password).0, payload)
        XCTAssertThrowsError(try VaultCrypto.changePassword(original, oldPassword: "wrong", newPassword: nextPassword))
    }
    func testBoundsRejectHostileInputsBeforeDerivation() throws {
        var params = KDFParameters(); params.memoryKiB = UInt32.max
        XCTAssertThrowsError(try params.derive(password: password, salt: Data(count: 16)))
        params = KDFParameters(); params.iterations = UInt32.max; XCTAssertThrowsError(try params.validate())
        params = KDFParameters(); params.lanes = 0; XCTAssertThrowsError(try params.validate())
        XCTAssertThrowsError(try VaultEnvelope.decode(Data(count: Limits.fileBytes + 1)))
        XCTAssertThrowsError(try VaultCrypto.validateNewPassword("short"))
        XCTAssertThrowsError(try VaultCrypto.validateNewPassword(String(repeating: "a", count: 30)))
    }
    func testGeneratorClassesAndBounds() throws {
        var options = PasswordOptions()
        for _ in 0..<50 {
            let value = try options.generate(); XCTAssertEqual(value.count, 24)
            XCTAssertTrue(value.contains(where: \.isUppercase)); XCTAssertTrue(value.contains(where: \.isLowercase)); XCTAssertTrue(value.contains(where: \.isNumber))
        }
        options.uppercase = false; options.lowercase = false; options.symbols = false
        XCTAssertTrue(try options.generate().allSatisfy(\.isNumber))
        options.digits = false; XCTAssertThrowsError(try options.generate())
        options.length = 1000; XCTAssertThrowsError(try options.generate())
    }
    func testAtomicInterruptedSaveAndConflict() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = VaultFile(url: directory.appendingPathComponent("test.stillwater"))
        let original = Data("fictional original ciphertext".utf8)
        try file.write(original, expected: nil)
        enum Interrupted: Error { case simulated }
        XCTAssertThrowsError(try file.write(Data("replacement".utf8), expected: VaultFile.digest(original), beforeCommit: { throw Interrupted.simulated }))
        XCTAssertEqual(try file.read(), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["test.stillwater"])
        XCTAssertThrowsError(try file.write(Data(), expected: Data(count: 32)))
        XCTAssertEqual(try file.read(), original)
        XCTAssertThrowsError(try file.write(Data(), expected: nil))
        let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try file.write(Data("new ciphertext".utf8), expected: VaultFile.digest(original))
        XCTAssertEqual(try file.read(), Data("new ciphertext".utf8))
    }
    func testSymlinkRefused() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target"); try Data("fictional".utf8).write(to: target)
        let link = directory.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try VaultFile(url: link).read())
    }
    func testIdleDeadlineAndActivity() {
        var policy = IdlePolicy(timeout: 60, now: 100)
        XCTAssertFalse(policy.shouldLock(now: 159)); XCTAssertTrue(policy.shouldLock(now: 160))
        policy.activity(now: 155); XCTAssertFalse(policy.shouldLock(now: 160)); XCTAssertTrue(policy.shouldLock(now: 215))
    }
}
