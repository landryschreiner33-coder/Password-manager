import SwiftUI
import AppKit

@main @MainActor struct StillwaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var session = VaultSession()
    @AppStorage("appearance") private var appearance = AppAppearance.dark.rawValue
    private var selectedAppearance: AppAppearance { AppAppearance(rawValue: appearance) ?? .dark }
    var body: some Scene {
        Window("Stillwater", id: "vault") {
            RootView().environmentObject(session)
                .frame(minWidth: 1000, minHeight: 660)
                .preferredColorScheme(selectedAppearance.colorScheme)
                .onAppear { selectedAppearance.apply() }
                .onChange(of: appearance) { selectedAppearance.apply() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in session.lock() }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { event in
                    if let window = event.object as? NSWindow, window.identifier?.rawValue == "vault" { session.lock() }
                }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Vault") {
                Button("Lock Vault") { session.lock() }.keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(!session.unlocked)
            }
        }
        Settings {
            PreferencesView().environmentObject(session).frame(width: 460).padding(28)
                .preferredColorScheme(selectedAppearance.colorScheme)
                .onAppear { selectedAppearance.apply() }
                .onChange(of: appearance) { selectedAppearance.apply() }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }
}
struct RootView: View {
    @EnvironmentObject private var session: VaultSession
    var body: some View {
        Group {
            if session.unlocked { VaultView() }
            else { UnlockView() }
        }
        .id(session.viewEpoch)
        .alert("Stillwater", isPresented: Binding(get: { session.message != nil }, set: { if !$0 { session.message = nil } })) {
            Button("OK") { session.message = nil }
        } message: { Text(session.message ?? "") }
        .privacySensitive()
    }
}
struct UnlockView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: VaultSession
    @State private var password = ""
    @State private var confirmation = ""
    @State private var restoring = false
    @State private var recovering = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill").font(.system(size: 52, weight: .light)).foregroundStyle(.tint).accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(session.exists ? "Welcome back" : "A private place for your passwords").font(.largeTitle.weight(.semibold))
                Text(session.exists ? "Unlock your vault to get started." : "Create your Stillwater vault. Everything stays on this Mac.").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                if !session.exists || recovering {
                    SecureField("Master password", text: $password).textContentType(.password).focused($focused)
                        .onSubmit { submit() }
                    if !session.exists {
                        SecureField("Confirm master password", text: $confirmation).onSubmit { submit() }
                        Text("Use at least 14 characters. Try a long phrase of unrelated words. Keep it somewhere safe: there is no password reset.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(action: submit) {
                        HStack { Spacer(); if session.busy { ProgressView().controlSize(.small) }; Text(session.exists ? (recovering ? "Recover with Master Password" : "Unlock Vault") : "Create Vault"); Spacer() }
                    }.buttonStyle(.borderedProminent).disabled(session.busy || password.isEmpty || (!session.exists && password != confirmation))
                }
                if session.exists {
                    if session.biometricEnabled {
                    Button { Task { await session.unlockWithTouchID() } } label: { Label("Unlock with Touch ID", systemImage: "touchid").frame(maxWidth: .infinity) }
                        .disabled(session.busy)
                    } else {
                        Text("Recover with your master password, then enable Touch ID in Settings for normal unlocking.").font(.callout).foregroundStyle(.secondary)
                    }
                    Button(recovering ? "Return to Touch ID" : "Recover with Master Password…") {
                        password = ""; recovering.toggle(); focused = recovering
                    }.buttonStyle(.link).disabled(session.busy)
                    if recovering { Text("Recovery uses your vault’s master password. Touch ID remains enabled for normal unlocking.").font(.caption).foregroundStyle(.secondary) }
                }
            }.textFieldStyle(.roundedBorder).controlSize(.large).frame(width: 360)
            Button("Restore an Encrypted Backup…") { restoring = true }.buttonStyle(.link).disabled(session.busy)
            Text("Offline. Private. Yours.").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VaultPalette(scheme: scheme).canvas)
        .tint(VaultPalette(scheme: scheme).accent)
        .onAppear { focused = true }
        .onDisappear { password = ""; confirmation = "" }
        .sheet(isPresented: $restoring) { RestoreView() }
    }
    private func submit() {
        guard !session.busy, !password.isEmpty, session.exists || password == confirmation else { return }
        let value = password; let recovery = recovering; password = ""; confirmation = ""
        Task { if session.exists { await session.unlock(password: value, recovery: recovery) } else { await session.create(password: value) } }
    }
}
