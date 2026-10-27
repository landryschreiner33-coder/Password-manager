import SwiftUI
import VaultCore

struct AccountEditor: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss
    @State var account: Account
    @State private var options = PasswordOptions()
    @State private var error: String?
    @State private var reveal = false
    @FocusState private var nameFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(account.name.isEmpty ? "Add an account" : "Edit account").font(.title2.bold())
            Form {
                TextField("Account name", text: $account.name).focused($nameFocused)
                TextField("Website", text: $account.website)
                TextField("Username or email", text: $account.username)
                HStack {
                    if reveal { TextField("Password", text: $account.password) } else { SecureField("Password", text: $account.password) }
                    Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }.accessibilityLabel(reveal ? "Hide password" : "Reveal password")
                }
                DisclosureGroup("Generate a strong password") {
                    Stepper("Length: \(options.length)", value: $options.length, in: 12...128)
                    HStack { Toggle("A–Z", isOn: $options.uppercase); Toggle("a–z", isOn: $options.lowercase); Toggle("0–9", isOn: $options.digits); Toggle("Symbols", isOn: $options.symbols) }
                    Button("Generate Password") { do { account.password = try options.generate() } catch { self.error = error.localizedDescription } }
                }
                Picker("Folder", selection: $account.folderID) {
                    Text("No folder").tag(Optional<UUID>.none)
                    ForEach(session.payload?.folders ?? []) { Text($0.name).tag(Optional($0.id)) }
                }
                Toggle("Favorite", isOn: $account.favorite)
                VStack(alignment: .leading) { Text("Private notes"); TextEditor(text: $account.notes).frame(height: 100).border(.quaternary) }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack { Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save Account") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 540).onAppear { nameFocused = true }
            .onDisappear { account = Account() }
    }
    private func save() { do { try session.save(account); dismiss() } catch { self.error = error.localizedDescription } }
}
