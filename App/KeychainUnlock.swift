import Foundation
import Security
import LocalAuthentication
import CryptoKit

protocol BiometricKeyStore {
    func save(_ key: SymmetricKey, id: UUID) throws
    func load(id: UUID, context: LAContext) throws -> SymmetricKey
    func remove(id: UUID) throws
}
struct KeychainUnlock: BiometricKeyStore {
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.stillwater.vault.unlock",
         kSecAttrAccount as String: id.uuidString,
         kSecUseDataProtectionKeychain as String: true]
    }
    func save(_ key: SymmetricKey, id: UUID) throws {
        let context = LAContext(); var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), context.biometryType == .touchID else { throw KeychainError.unavailable }
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &accessError) else { throw KeychainError.unavailable }
        try remove(id: id)
        var bytes = key.withUnsafeBytes { Data($0) }; defer { bytes.resetBytes(in: 0..<bytes.count) }
        var request = query(id)
        request[kSecAttrAccessControl as String] = access
        request[kSecValueData as String] = bytes
        guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw KeychainError.unavailable }
    }
    func load(id: UUID, context: LAContext) throws -> SymmetricKey {
        context.localizedReason = "Unlock your Stillwater vault"
        context.touchIDAuthenticationAllowableReuseDuration = 0
        var request = query(id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        guard status == errSecSuccess, var bytes = result as? Data, bytes.count == 32 else {
            if status == errSecUserCanceled || status == errSecAuthFailed { throw KeychainError.cancelled }
            throw KeychainError.unavailable
        }
        defer { bytes.resetBytes(in: 0..<bytes.count) }
        return SymmetricKey(data: bytes)
    }
    func remove(id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unavailable }
    }
}
enum KeychainError: Error, LocalizedError {
    case unavailable, cancelled
    var errorDescription: String? {
        switch self {
        case .cancelled: return "Touch ID was cancelled. You can use your master password."
        case .unavailable: return "Touch ID is unavailable. Use your master password."
        }
    }
}
