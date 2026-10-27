import SwiftUI
import VaultCore
import AppKit

struct VaultView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.colorScheme) private var scheme
    @State private var scope: String? = "all"
    @State private var selection: UUID?
    @State private var search = ""
    @State private var editor: Account?
    @State private var importing = false
    @State private var restoring = false
    @State private var newFolder = false
    @State private var folderName = ""
    @State private var deleteAccount: Account?
    @FocusState private var searchFocused: Bool
    private var palette: VaultPalette { VaultPalette(scheme: scheme) }
    private var scopeTitle: String {
        if scope == "favorites" { return "Favorites" }
        return session.payload?.folders.first(where: { $0.id.uuidString == scope })?.name ?? "All Accounts"
    }
    private var accounts: [Account] {
        (session.payload?.accounts ?? []).filter { account in
            (scope == "all" || (scope == "favorites" && account.favorite) || account.folderID?.uuidString == scope) &&
            (search.isEmpty || [account.name, account.username, account.website].contains { $0.localizedCaseInsensitiveContains(search) })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield").font(.system(size: 20, weight: .medium)).foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Personal vault").font(.system(size: 13, weight: .semibold))
                        Text("On this Mac").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.horizontal, 20).padding(.vertical, 24)
                List(selection: $scope) {
                    Section("Library") {
                        Label("All Accounts", systemImage: "key.horizontal").tag("all")
                        Label("Favorites", systemImage: "star").tag("favorites")
                    }
                    Section("Folders") {
                        ForEach(session.payload?.folders ?? []) { folder in
                            Label(folder.name, systemImage: "folder").tag(folder.id.uuidString)
                                .contextMenu {
                                    Button("Remove Folder (Keep Accounts)") {
                                        perform { try session.removeFolder(folder.id); scope = "all" }
                                    }
                                }
                        }
                        Button { newFolder = true } label: {
                            Label("New Folder", systemImage: "folder.badge.plus").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                VStack(alignment: .leading, spacing: 14) {
                    Divider()
                    Label("Stored on this Mac", systemImage: "internaldrive").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button { session.lock() } label: {
                        HStack { Label("Lock Vault", systemImage: "lock"); Spacer(); Text("⇧⌘L").foregroundStyle(.secondary).accessibilityHidden(true) }
                    }.controlSize(.large).help("Lock vault (⇧⌘L)")
                }.padding(18)
            }.background(palette.sidebar).navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } content: {
            VStack(spacing: 0) {
                HStack {
                    Text(scopeTitle).font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text("\(accounts.count)").font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(palette.surface, in: Capsule())
                        .accessibilityLabel("\(accounts.count) accounts")
                }.padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 18)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("Search accounts", text: $search).textFieldStyle(.plain).focused($searchFocused)
                        .accessibilityLabel("Search accounts by name, username, or website")
                    Text("⌘F").font(.system(size: 11)).foregroundStyle(.secondary).accessibilityHidden(true)
                }.padding(.horizontal, 12).padding(.vertical, 10)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(searchFocused ? palette.accent : Color.primary.opacity(0.12), lineWidth: searchFocused ? 2 : 1))
                    .padding(.horizontal, 16).padding(.bottom, 12)
                List(accounts, selection: $selection) { account in
                    HStack(spacing: 12) {
                        Image(systemName: "key.horizontal").font(.system(size: 16, weight: .medium)).foregroundStyle(palette.accent)
                            .frame(width: 34, height: 34).background(palette.surface, in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(account.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(account.username.isEmpty ? account.website : account.username).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if account.favorite { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.secondary).accessibilityLabel("Favorite") }
                    }.padding(.vertical, 10).tag(account.id)
                }.listStyle(.inset).scrollContentBackground(.hidden).overlay {
                    if accounts.isEmpty { ContentUnavailableView(search.isEmpty ? "Your vault starts here" : "No matching accounts", systemImage: "key", description: Text(search.isEmpty ? "Add an account or import a password CSV." : "Try a different name, website, or username.")) }
                }
                HStack { Text("\(accounts.count) accounts").font(.system(size: 11)).foregroundStyle(.secondary); Spacer() }.padding(18)
            }.background(palette.list).navigationSplitViewColumnWidth(min: 270, ideal: 320)
        } detail: {
            Group {
                if let account = accounts.first(where: { $0.id == selection }) {
                    AccountDetail(account: account, edit: { editor = account }, delete: { deleteAccount = account }).id(account.id)
                } else { ContentUnavailableView("Your accounts, within reach", systemImage: "lock.shield", description: Text("Choose an account to view its details.")) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(palette.canvas)
        }
        .tint(palette.accent)
        .navigationTitle("Stillwater")
        .toolbar {
            ToolbarItemGroup {
                Button { searchFocused = true } label: { Label("Find Account", systemImage: "magnifyingglass") }.keyboardShortcut("f")
                Button { editor = Account() } label: { Label("Add Account", systemImage: "plus") }
                    .labelStyle(.titleAndIcon).keyboardShortcut("n").help("Add an account (⌘N)")
                Menu {
                    Button("Import Password CSV…") { importing = true }
                    Button("Export Encrypted Backup…", action: export)
                    Button("Restore Encrypted Backup…") { restoring = true }
                    Divider()
                    SettingsLink { Text("Settings…") }
                } label: { Label("Vault Actions", systemImage: "ellipsis.circle") }
                Button { session.lock() } label: { Label("Lock Vault", systemImage: "lock") }
            }
        }
        .sheet(item: $editor) { AccountEditor(account: $0) }
        .sheet(isPresented: $importing) { ImportView() }
        .sheet(isPresented: $restoring) { RestoreView() }
        .alert("New Folder", isPresented: $newFolder) {
            TextField("Folder name", text: $folderName)
            Button("Cancel", role: .cancel) { folderName = "" }
            Button("Create") { perform { try session.addFolder(folderName) }; folderName = "" }
        }
        .alert("Delete this account?", isPresented: Binding(get: { deleteAccount != nil }, set: { if !$0 { deleteAccount = nil } })) {
            Button("Cancel", role: .cancel) { deleteAccount = nil }
            Button("Delete", role: .destructive) { if let account = deleteAccount { perform { try session.delete(account.id) } }; deleteAccount = nil }
        } message: { Text("This cannot be undone. An older encrypted backup may still contain the account.") }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { session.message = error.localizedDescription } }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Stillwater Backup.stillwater"; panel.title = "Export Encrypted Backup"
        panel.message = "Keep this encrypted file somewhere safe. Restoring it requires your current master password."
        if panel.runModal() == .OK, let url = panel.url, session.unlocked { perform { try session.exportBackup(to: url) } }
    }
}
struct AccountDetail: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.colorScheme) private var scheme
    let account: Account
    var edit: () -> Void
    var delete: () -> Void
    @State private var revealed = false
    @State private var copied = false
    private var palette: VaultPalette { VaultPalette(scheme: scheme) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Account details").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button { var next = account; next.favorite.toggle(); do { try session.save(next) } catch { session.message = error.localizedDescription } } label: {
                        Image(systemName: account.favorite ? "star.fill" : "star")
                    }.accessibilityLabel(account.favorite ? "Remove from favorites" : "Add to favorites")
                    Button("Edit Account", action: edit).keyboardShortcut("e")
                }
                HStack(spacing: 16) {
                    Image(systemName: "key.horizontal").font(.system(size: 23, weight: .medium)).foregroundStyle(palette.accent)
                        .frame(width: 54, height: 54).background(palette.surface, in: RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(account.name).font(.system(size: 27, weight: .semibold)).textSelection(.enabled)
                        Text(account.website.isEmpty ? "Account" : account.website).font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 8)
                VaultCard {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            field("Username or email", value: account.username)
                            Spacer()
                            if !account.username.isEmpty {
                                Button { session.clipboard.copy(account.username) } label: { Image(systemName: "doc.on.doc") }
                                    .accessibilityLabel("Copy username").help("Copy username")
                            }
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Password").font(.system(size: 12)).foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Text(revealed ? account.password : "••••••••••••").font(.system(size: 15, design: .monospaced)).textSelection(.disabled)
                                    .accessibilityLabel(revealed ? account.password : "Password hidden")
                                Spacer(minLength: 8)
                                Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye") }
                                    .accessibilityLabel(revealed ? "Hide password" : "Reveal password")
                                Button { session.clipboard.copy(account.password); copied = true } label: {
                                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                }.help("Clipboard clears after 30 seconds")
                            }
                        }
                    }
                }
                if !account.notes.isEmpty {
                    VaultCard { field("Private notes", value: account.notes) }
                }
                if let folder = session.payload?.folders.first(where: { $0.id == account.folderID }) {
                    Label(folder.name, systemImage: "folder").font(.system(size: 12)).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 7).background(palette.surface, in: Capsule())
                }
                Divider().padding(.top, 4)
                HStack(alignment: .firstTextBaseline) {
                    Text("Updated \(account.modified.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete Account…", role: .destructive, action: delete).controlSize(.small)
                }
            }.padding(32).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: revealed) { if revealed { try? await Task.sleep(for: .seconds(15)); if !Task.isCancelled { revealed = false } } }
        .task(id: copied) { if copied { try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { copied = false } } }
    }
    private func field(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
