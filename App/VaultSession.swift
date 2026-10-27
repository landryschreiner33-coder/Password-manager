import SwiftUI
import AppKit
import CryptoKit
import LocalAuthentication
import VaultCore

@MainActor final class VaultSession: ObservableObject {
    @Published private(set) var payload: VaultPayload?
    @Published private(set) var viewEpoch = UUID()
    @Published private(set) var exists = false
    @Published private(set) var busy = false
    @Published var message: String?
    @Published var timeoutMinutes: Double = 5 {
        didSet { UserDefaults.standard.set(timeoutMinutes, forKey: "idleMinutes"); idle.timeout = timeoutMinutes * 60 }
    }
    @Published private(set) var biometricEnabled = false
    @Published var benchmarkText = ""
    let clipboard = SensitiveClipboard()
    private var file: VaultFile?
    private var envelope: VaultEnvelope?
    private var key: SymmetricKey?
    private var digest: Data?
    private var generation = UUID()
    private var context: LAContext?
    private var idle = IdlePolicy(timeout: 300, now: ProcessInfo.processInfo.systemUptime)
    private var timer: Timer?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private let keychain: BiometricKeyStore
    init(keychain: BiometricKeyStore = KeychainUnlock(), url: URL? = nil, monitor: Bool = true) {
        self.keychain = keychain
        do {
            let location: URL
            if let url { location = url }
            else {
                let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Stillwater", isDirectory: true)
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
                location = base.appendingPathComponent("Vault.stillwater")
            }
            file = VaultFile(url: location)
            exists = FileManager.default.fileExists(atPath: location.path)
        } catch { message = "The vault folder is unavailable. Check your Mac’s storage and permissions." }
        let saved = UserDefaults.standard.double(forKey: "idleMinutes")
        if [1.0, 2, 5, 10, 15].contains(saved) { timeoutMinutes = saved; idle.timeout = saved * 60 }
        if monitor { installMonitoring() }
    }
    var unlocked: Bool { payload != nil }
    private func installMonitoring() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved, .scrollWheel]) { [weak self] event in
            self?.activity(); return event
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIdle() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        })
    }
    func activity() { idle.activity(now: ProcessInfo.processInfo.systemUptime) }
    func checkIdle() { if unlocked && idle.shouldLock(now: ProcessInfo.processInfo.systemUptime) { lock() } }
    func lock() {
        generation = UUID(); viewEpoch = UUID(); context?.invalidate(); context = nil
        payload = nil; key = nil; envelope = nil; digest = nil; busy = false; message = nil
        clipboard.clear()
    }
    private func accept(_ payload: VaultPayload, key: SymmetricKey, envelope: VaultEnvelope, bytes: Data) {
        self.payload = payload; self.key = key; self.envelope = envelope; digest = VaultFile.digest(bytes)
        exists = true; biometricEnabled = UserDefaults.standard.bool(forKey: "touchID.\(envelope.header.id)")
        activity()
    }
    func create(password: String) async {
        guard !busy, !exists, let file else { return }
        busy = true; let token = generation
        do {
            let (envelope, key) = try await Task.detached { try VaultCrypto.create(password: password) }.value
            guard generation == token else { return }
            let bytes = try envelope.encoded(); try file.write(bytes, expected: nil)
            accept(VaultPayload(), key: key, envelope: envelope, bytes: bytes)
        } catch { if generation == token { message = error.localizedDescription } }
        if generation == token { busy = false }
    }
    func unlock(password: String) async {
        guard !busy, let file else { return }
        busy = true; let token = generation
        do {
            let bytes = try file.read(); let envelope = try VaultEnvelope.decode(bytes)
            let (payload, key) = try await Task.detached { try VaultCrypto.unlock(envelope, password: password) }.value
            guard generation == token else { return }
            accept(payload, key: key, envelope: envelope, bytes: bytes)
        } catch { if generation == token { message = error.localizedDescription } }
        if generation == token { busy = false }
    }
    func unlockWithTouchID() async {
        guard !busy, let file else { return }
        busy = true; let token = generation; let auth = LAContext(); context = auth
        do {
            let bytes = try file.read(); let envelope = try VaultEnvelope.decode(bytes); let store = keychain
            let key = try await Task.detached { try store.load(id: envelope.header.id, context: auth) }.value
            guard generation == token else { return }
            let payload = try VaultCrypto.decrypt(envelope, key: key)
            accept(payload, key: key, envelope: envelope, bytes: bytes)
        } catch { if generation == token { message = error.localizedDescription } }
        auth.invalidate()
        if generation == token { context = nil; busy = false }
    }
    func commit(_ next: VaultPayload) throws {
        guard let envelope, let key, let file, let digest, unlocked else { throw VaultError.authentication }
        let replacement = try VaultCrypto.encrypt(next, key: key, envelope: envelope)
        let bytes = try replacement.encoded(); try file.write(bytes, expected: digest)
        self.envelope = replacement; self.digest = VaultFile.digest(bytes); payload = next; activity()
    }
    func save(_ account: Account) throws {
        guard var next = payload else { throw VaultError.authentication }
        var account = account; account.modified = Date(); try account.validate()
        if let index = next.accounts.firstIndex(where: { $0.id == account.id }) { next.accounts[index] = account }
        else { next.accounts.append(account) }
        try commit(next)
    }
    func delete(_ id: UUID) throws { guard var next = payload else { return }; next.accounts.removeAll { $0.id == id }; try commit(next) }
    func addFolder(_ name: String) throws { guard var next = payload else { return }; next.folders.append(Folder(name: name)); try commit(next) }
    func removeFolder(_ id: UUID) throws {
        guard var next = payload else { return }
        next.folders.removeAll { $0.id == id }
        for i in next.accounts.indices where next.accounts[i].folderID == id { next.accounts[i].folderID = nil }
        try commit(next)
    }
    func setBiometrics(_ enabled: Bool, password: String) async {
        guard !busy, let envelope else { return }; busy = true; let token = generation
        do {
            if enabled {
                let (_, verifiedKey) = try await Task.detached { try VaultCrypto.unlock(envelope, password: password) }.value
                guard token == generation else { return }; try keychain.save(verifiedKey, id: envelope.header.id)
            } else { try keychain.remove(id: envelope.header.id) }
            biometricEnabled = enabled; UserDefaults.standard.set(enabled, forKey: "touchID.\(envelope.header.id)")
        } catch { if token == generation { message = error.localizedDescription } }
        if token == generation { busy = false }
    }
    func changePassword(old: String, new: String) async {
        guard !busy, let envelope, let file, let digest else { return }; busy = true; let token = generation
        do {
            let replacement = try await Task.detached { try VaultCrypto.changePassword(envelope, oldPassword: old, newPassword: new) }.value
            guard token == generation else { return }
            let bytes = try replacement.encoded()
            try keychain.remove(id: envelope.header.id)
            biometricEnabled = false; UserDefaults.standard.removeObject(forKey: "touchID.\(envelope.header.id)")
            try file.write(bytes, expected: digest)
            lock()
            message = "Master password changed. Make a new backup. Unlock with your new password. Older backups still use the previous password. Touch ID has been turned off."
        } catch { if token == generation { message = error.localizedDescription } }
        if token == generation { busy = false }
    }
    func exportBackup(to url: URL) throws {
        guard let envelope else { throw VaultError.authentication }
        let target = VaultFile(url: url)
        let expected = FileManager.default.fileExists(atPath: url.path) ? VaultFile.digest(try target.read()) : nil
        try target.write(envelope.encoded(), expected: expected)
    }
    func restore(from url: URL, password: String) async {
        guard !busy, let file else { return }; busy = true; let token = generation
        do {
            let bytes = try VaultFile(url: url).read(); let restored = try VaultEnvelope.decode(bytes)
            let (payload, key) = try await Task.detached { try VaultCrypto.unlock(restored, password: password) }.value
            guard generation == token else { return }
            let current: Data? = exists ? try file.read() : nil
            if let current, let previous = try? VaultEnvelope.decode(current) { try keychain.remove(id: previous.header.id) }
            try keychain.remove(id: restored.header.id)
            UserDefaults.standard.removeObject(forKey: "touchID.\(restored.header.id)")
            try file.write(bytes, expected: current.map(VaultFile.digest))
            accept(payload, key: key, envelope: restored, bytes: bytes)
        } catch { if token == generation { message = error.localizedDescription } }
        if token == generation { busy = false }
    }
    func benchmark() async {
        do {
            let duration = try await Task.detached { try KDFParameters().benchmark() }.value
            benchmarkText = String(format: "Unlock preparation: %.2f seconds on this Mac (64 MiB, 3 passes).", duration)
        } catch { message = error.localizedDescription }
    }
}
