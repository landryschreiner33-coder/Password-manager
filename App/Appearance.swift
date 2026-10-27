import SwiftUI
import AppKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    @MainActor func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// Quiet, opaque surfaces keep the vault readable with Reduce Transparency enabled.
struct VaultPalette {
    let scheme: ColorScheme
    private var dark: Bool { scheme == .dark }
    var sidebar: Color { dark ? Color(red: 0.063, green: 0.075, blue: 0.094) : Color(nsColor: .windowBackgroundColor) }
    var list: Color { dark ? Color(red: 0.083, green: 0.094, blue: 0.114) : Color(nsColor: .controlBackgroundColor) }
    var canvas: Color { dark ? Color(red: 0.071, green: 0.082, blue: 0.102) : Color(red: 0.97, green: 0.975, blue: 0.98) }
    var surface: Color { dark ? Color(red: 0.106, green: 0.122, blue: 0.149) : .white }
    var accent: Color { dark ? Color(red: 0.58, green: 0.70, blue: 0.94) : Color(red: 0.22, green: 0.37, blue: 0.65) }
}

struct VaultCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VaultPalette(scheme: scheme).surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : 0.09), lineWidth: 1))
    }
}
