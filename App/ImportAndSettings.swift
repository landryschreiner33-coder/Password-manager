import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VaultCore

struct ImportView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss
    @State private var table: CSVTable?
    @State private var mapping = CSVMapping(headers: [])
    @State private var preview: [Account] = []
    @State private var keepDuplicates = false
    @State private var error: String?
    @State private var reviewed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Import accounts").font(.title2.bold())
            Text("Choose a UTF-8 CSV, match its columns, then review. Your existing accounts will never be overwritten.").foregroundStyle(.secondary)
            Button("Choose CSV…", action: choose)
            if let table {
                Text("\(table.rows.count) rows found").font(.headline)
                Form {
                    column("Account name", selection: $mapping.name, headers: table.headers)
                    column("Website", selection: $mapping.website, headers: table.headers)
                    column("Username or email", selection: $mapping.username, headers: table.headers)
                    column("Password", selection: $mapping.password, headers: table.headers)
                    column("Private notes", selection: $mapping.notes, headers: table.headers)
                }
                Button("Validate and Preview") {
                    do { preview = try mapping.accounts(from: table); reviewed = true; error = nil }
                    catch { reviewed = false; self.error = "Check your column choices and rows. Each account needs a name and password; columns must be distinct and fields must fit the size limits." }
                }
                if reviewed {
                    List(preview.prefix(100)) { item in
                        HStack { VStack(alignment: .leading) { Text(item.name); Text(item.username).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("••••••••").accessibilityLabel("Password hidden") }
                    }.frame(height: 150)
                    Text("Showing the first \(min(preview.count, 100)) of \(preview.count) accounts. Passwords and private notes stay hidden.").font(.caption)
                    Text("\(ImportPlan.duplicateCount(preview, existing: session.payload?.accounts ?? [])) duplicates found (matching name, website, and username).")
                    Picker("Duplicates", selection: $keepDuplicates) { Text("Skip duplicates").tag(false); Text("Keep both copies").tag(true) }.pickerStyle(.segmented)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Import Accounts") { apply() }.buttonStyle(.borderedProminent).disabled(!reviewed || preview.isEmpty) }
        }.padding(28).frame(width: 600)
        .onChange(of: mapping.name) { reviewed = false }
        .onChange(of: mapping.website) { reviewed = false }
        .onChange(of: mapping.username) { reviewed = false }
        .onChange(of: mapping.password) { reviewed = false }
        .onChange(of: mapping.notes) { reviewed = false }
        .onDisappear { table = nil; preview = [] }
    }
    private func column(_ title: String, selection: Binding<Int>, headers: [String]) -> some View {
        Picker(title, selection: selection) { Text("Not imported").tag(-1); ForEach(headers.indices, id: \.self) { Text(headers[$0]).tag($0) } }
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, session.unlocked {
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { table = try CSVTable(data: VaultFile(url: url).read()); mapping = CSVMapping(headers: table!.headers); preview = []; reviewed = false; error = nil }
            catch { self.error = "This CSV cannot be imported. Use UTF-8 with a header row, consistent columns, and a file smaller than 8 MiB." }
        }
    }
    private func apply() {
        do { guard let payload = session.payload else { return }; try session.commit(ImportPlan.apply(preview, to: payload, keepDuplicates: keepDuplicates)); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
struct RestoreView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var password = ""
    @State private var confirmed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Restore an encrypted backup").font(.title2.bold())
            Text("Use the master password from when the backup was made. Touch ID is not needed. Restoring replaces the vault on this Mac; export a current backup first.").foregroundStyle(.secondary)
            Button("Choose Backup…") {
                let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
                if panel.runModal() == .OK { url = panel.url }
            }.disabled(session.busy)
            if let url { Text(url.lastPathComponent).lineLimit(1) }
            SecureField("Backup’s master password", text: $password)
            if session.exists { Toggle("I have backed up my current vault and want to replace it.", isOn: $confirmed) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.disabled(session.busy)
                Spacer()
                if session.busy { ProgressView().controlSize(.small) }
                Button("Restore Backup") {
                    guard let url else { return }
                    let value = password; password = ""
                    Task {
                        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        await session.restore(from: url, password: value)
                        if session.message == nil { dismiss() }
                    }
                }.buttonStyle(.borderedProminent).disabled(url == nil || password.isEmpty || session.busy || (session.exists && !confirmed))
            }
        }.padding(28).frame(width: 480).onDisappear { password = ""; url = nil }
    }
}
struct PreferencesView: View {
    @AppStorage("appearance") private var appearance = AppAppearance.dark.rawValue
    @EnvironmentObject private var session: VaultSession
    @State private var old = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var biometricPassword = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Vault settings").font(.title2.bold())
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
            }.pickerStyle(.segmented)
            Divider()
            Picker("Lock after inactivity", selection: $session.timeoutMinutes) {
                ForEach([1.0, 2, 5, 10, 15], id: \.self) { Text("\(Int($0)) minutes").tag($0) }
            }
            Text("Also locks when your Mac sleeps or the screen locks. Copied passwords clear after 30 seconds if the clipboard is unchanged.").font(.caption).foregroundStyle(.secondary)
            if session.unlocked {
                Divider()
                Text("Touch ID").font(.headline)
                if session.biometricEnabled {
                    Button("Turn Off Touch ID") { Task { await session.setBiometrics(false, password: "") } }
                } else {
                    SecureField("Master password", text: $biometricPassword)
                    Button("Enable Touch ID") { let value = biometricPassword; biometricPassword = ""; Task { await session.setBiometrics(true, password: value) } }.disabled(biometricPassword.isEmpty)
                }
                Divider()
                DisclosureGroup("Change master password") {
                    VStack(spacing: 12) {
                        SecureField("Current master password", text: $old)
                        SecureField("New master password", text: $new)
                        SecureField("Confirm new master password", text: $confirmation)
                        Button("Change Master Password") {
                            let previous = old, next = new; clear()
                            Task { await session.changePassword(old: previous, new: next) }
                        }.disabled(old.isEmpty || new != confirmation || new.count < 14)
                    }.padding(.top, 12)
                }
                Button("Check Unlock Speed") { Task { await session.benchmark() } }
                if !session.benchmarkText.isEmpty { Text(session.benchmarkText).font(.caption).foregroundStyle(.secondary) }
            } else { Text("Unlock your vault to manage Touch ID and your master password.").foregroundStyle(.secondary) }
            Text("Stillwater is unaudited. Independent security review is required before storing real passwords.").font(.caption).foregroundStyle(.secondary)
        }.disabled(session.busy).onChange(of: session.unlocked) { if !session.unlocked { clear() } }.onDisappear(perform: clear)
    }
    private func clear() { old = ""; new = ""; confirmation = ""; biometricPassword = "" }
}
