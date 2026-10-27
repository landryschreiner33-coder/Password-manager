import Foundation

public enum VaultError: Error, LocalizedError {
    case invalidFile, authentication, weakPassword, invalidEntry, tooLarge, storage, changedOnDisk, random, generator
    public var errorDescription: String? {
        switch self {
        case .authentication: return "The password is incorrect, or this vault cannot be opened."
        case .weakPassword: return "Use at least 14 characters. A long phrase of unrelated words works well."
        case .invalidEntry: return "Check the account fields. A name and password are required."
        case .tooLarge: return "This file is too large to open safely."
        case .storage: return "The vault could not be saved. Your previous file has been preserved."
        case .changedOnDisk: return "The vault changed outside this window. Lock and reopen it before saving."
        case .random: return "Secure random generation is unavailable. Try again."
        case .generator: return "Choose at least one character type and a length from 12 to 128."
        case .invalidFile: return "This file is damaged or uses an unsupported format."
        }
    }
}
public struct Account: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var name = ""
    public var website = ""
    public var username = ""
    public var password = ""
    public var notes = ""
    public var folderID: UUID?
    public var favorite = false
    public var modified = Date()
    public init() {}
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty,
              name.utf8.count <= 1024, website.utf8.count <= 4096, username.utf8.count <= 4096,
              password.utf8.count <= 4096, notes.utf8.count <= 65536 else { throw VaultError.invalidEntry }
    }
    public var duplicateKey: [String] {
        [name, website, username].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }
}
public struct Folder: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public init(name: String) { self.name = name }
}
public struct VaultPayload: Codable, Equatable {
    public var accounts: [Account] = []
    public var folders: [Folder] = []
    public init() {}
    public func validate() throws {
        guard accounts.count <= 10000, folders.count <= 500,
              Set(accounts.map(\.id)).count == accounts.count,
              Set(folders.map(\.id)).count == folders.count,
              folders.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.utf8.count <= 256 }) else { throw VaultError.invalidFile }
        let ids = Set(folders.map(\.id))
        for account in accounts {
            try account.validate()
            if let folder = account.folderID, !ids.contains(folder) { throw VaultError.invalidFile }
        }
    }
}
public enum Limits { public static let fileBytes = 16 * 1024 * 1024 }
public struct IdlePolicy {
    public var timeout: TimeInterval
    public var lastActivity: TimeInterval
    public init(timeout: TimeInterval, now: TimeInterval) { self.timeout = timeout; lastActivity = now }
    public mutating func activity(now: TimeInterval) { lastActivity = now }
    public func shouldLock(now: TimeInterval) -> Bool { now - lastActivity >= timeout }
}
