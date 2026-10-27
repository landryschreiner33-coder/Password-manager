import Foundation
import CryptoKit
import Security
import Clibsodium

public enum SecureRandom {
    public static func bytes(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard result == errSecSuccess else { throw VaultError.random }
        return data
    }
    public static func index(_ upperBound: Int) throws -> Int {
        precondition(upperBound > 0 && upperBound <= 256)
        let limit = 256 - 256 % upperBound
        while true { let n = Int(try bytes(1)[0]); if n < limit { return n % upperBound } }
    }
}
public struct KDFParameters: Codable, Equatable {
    public var algorithm = "argon2id"
    public var version = 19
    public var memoryKiB: UInt32 = 65536
    public var iterations: UInt32 = 3
    public var lanes: UInt32 = 1
    public init() {}
    public func validate() throws {
        guard algorithm == "argon2id", version == 19, (65536...262144).contains(memoryKiB),
              (3...10).contains(iterations), lanes == 1 else { throw VaultError.invalidFile }
    }
    public func derive(password: String, salt: Data) throws -> SymmetricKey {
        try validate()
        guard salt.count == 16, !password.isEmpty, password.utf8.count <= 1024 else { throw VaultError.invalidFile }
        var passwordBytes = Array(password.utf8)
        var output = Data(count: 32)
        defer { passwordBytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }; output.resetBytes(in: 0..<output.count) }
        guard sodium_init() >= 0 else { throw VaultError.random }
        let code = passwordBytes.withUnsafeBytes { p in
            salt.withUnsafeBytes { s in
                output.withUnsafeMutableBytes { o in
                    crypto_pwhash_argon2id(o.baseAddress!.assumingMemoryBound(to: UInt8.self), UInt64(o.count), p.baseAddress!.assumingMemoryBound(to: CChar.self), UInt64(p.count), s.baseAddress!.assumingMemoryBound(to: UInt8.self), UInt64(iterations), Int(memoryKiB) * 1024, crypto_pwhash_argon2id_alg_argon2id13())
                }
            }
        }
        guard code == 0 else { throw VaultError.authentication }
        return SymmetricKey(data: output)
    }
    public func benchmark() throws -> TimeInterval {
        let start = ProcessInfo.processInfo.systemUptime
        _ = try derive(password: "fictional benchmark phrase", salt: SecureRandom.bytes(16))
        return ProcessInfo.processInfo.systemUptime - start
    }
}
public struct VaultHeader: Codable, Equatable {
    public var format = 1
    public var id: UUID
    public var kdf: KDFParameters
    public var salt: Data
}
public struct VaultEnvelope: Codable {
    public var header: VaultHeader
    public var wrappedKey: Data
    public var ciphertext: Data
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= Limits.fileBytes else { throw VaultError.tooLarge }
        do {
            let envelope = try JSONDecoder().decode(Self.self, from: data)
            try envelope.header.kdf.validate()
            guard envelope.header.format == 1, envelope.header.salt.count == 16,
                  envelope.wrappedKey.count == 60, envelope.ciphertext.count >= 28 else { throw VaultError.invalidFile }
            return envelope
        } catch { throw VaultError.invalidFile }
    }
    public func encoded() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= Limits.fileBytes else { throw VaultError.tooLarge }
        return data
    }
}
public enum VaultCrypto {
    private static func aad(_ header: VaultHeader, purpose: String) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return Data(("Stillwater/v1/" + purpose + "/").utf8) + (try encoder.encode(header))
    }
    private static func seal(_ data: Data, key: SymmetricKey, header: VaultHeader, purpose: String) throws -> Data {
        // CryptoKit obtains a fresh random nonce for each call.
        guard let combined = try AES.GCM.seal(data, using: key, authenticating: aad(header, purpose: purpose)).combined else { throw VaultError.invalidFile }
        return combined
    }
    public static func create(password: String, payload: VaultPayload = VaultPayload()) throws -> (VaultEnvelope, SymmetricKey) {
        try validateNewPassword(password)
        let key = SymmetricKey(data: try SecureRandom.bytes(32))
        let header = VaultHeader(id: UUID(), kdf: KDFParameters(), salt: try SecureRandom.bytes(16))
        return (try wrap(password: password, key: key, header: header, payload: payload), key)
    }
    public static func validateNewPassword(_ password: String) throws {
        guard password.count >= 14, password.utf8.count <= 1024,
              Set(password).count >= 6 else { throw VaultError.weakPassword }
    }
    private static func wrap(password: String, key: SymmetricKey, header: VaultHeader, payload: VaultPayload) throws -> VaultEnvelope {
        let wrapping = try header.kdf.derive(password: password, salt: header.salt)
        var raw = key.withUnsafeBytes { Data($0) }
        defer { raw.resetBytes(in: 0..<raw.count) }
        let wrapped = try seal(raw, key: wrapping, header: header, purpose: "key")
        return try encrypt(payload, key: key, envelope: VaultEnvelope(header: header, wrappedKey: wrapped, ciphertext: Data()))
    }
    public static func unlock(_ envelope: VaultEnvelope, password: String) throws -> (VaultPayload, SymmetricKey) {
        do {
            let wrapping = try envelope.header.kdf.derive(password: password, salt: envelope.header.salt)
            var raw = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.wrappedKey), using: wrapping, authenticating: aad(envelope.header, purpose: "key"))
            defer { raw.resetBytes(in: 0..<raw.count) }
            guard raw.count == 32 else { throw VaultError.authentication }
            let key = SymmetricKey(data: raw)
            return (try decrypt(envelope, key: key), key)
        } catch { throw VaultError.authentication }
    }
    public static func decrypt(_ envelope: VaultEnvelope, key: SymmetricKey) throws -> VaultPayload {
        var plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.ciphertext), using: key, authenticating: aad(envelope.header, purpose: "payload"))
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        let payload = try JSONDecoder().decode(VaultPayload.self, from: plaintext)
        try payload.validate(); return payload
    }
    public static func encrypt(_ payload: VaultPayload, key: SymmetricKey, envelope: VaultEnvelope) throws -> VaultEnvelope {
        try payload.validate()
        var plaintext = try JSONEncoder().encode(payload)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        var result = envelope
        result.ciphertext = try seal(plaintext, key: key, header: envelope.header, purpose: "payload")
        _ = try result.encoded()
        return result
    }
    public static func changePassword(_ envelope: VaultEnvelope, oldPassword: String, newPassword: String) throws -> VaultEnvelope {
        try validateNewPassword(newPassword)
        let (payload, _) = try unlock(envelope, password: oldPassword)
        let key = SymmetricKey(data: try SecureRandom.bytes(32))
        var header = envelope.header; header.salt = try SecureRandom.bytes(16); header.kdf = KDFParameters()
        return try wrap(password: newPassword, key: key, header: header, payload: payload)
    }
}
public struct PasswordOptions {
    public var length = 24
    public var uppercase = true
    public var lowercase = true
    public var digits = true
    public var symbols = true
    public init() {}
    public func generate() throws -> String {
        let groups = [(uppercase, "ABCDEFGHIJKLMNOPQRSTUVWXYZ"), (lowercase, "abcdefghijklmnopqrstuvwxyz"), (digits, "0123456789"), (symbols, "!@#$%^&*()-_=+[]{}:,.?")].filter { $0.0 }.map { Array($0.1) }
        guard !groups.isEmpty, (12...128).contains(length) else { throw VaultError.generator }
        let alphabet = groups.flatMap { $0 }
        // Rejection sampling gives uniform output among strings meeting all selected classes.
        while true {
            let result = try (0..<length).map { _ in alphabet[try SecureRandom.index(alphabet.count)] }
            if groups.allSatisfy({ group in result.contains(where: { group.contains($0) }) }) { return String(result) }
        }
    }
}
