# Stillwater

A native, offline password vault for macOS 14 and later, written in Swift and SwiftUI. Accounts, folders, favorites, and private notes are encrypted together. The app includes password generation, mapped CSV import, encrypted backups, automatic locking, and Touch ID unlocking with master-password recovery.

**Unaudited development build. Do not entrust real passwords to it until the Mac validation checklist and independent security review are complete.** The project was authored on Linux. [Automated macOS validation](https://github.com/landryschreiner33-coder/Password-manager/actions/runs/40522887680) now passes Core testing, app compilation and session testing, and Release compilation. A notarized installer is not provided; physical-Mac security and usability checks remain required.

## Build and install on your Mac

1. Install Xcode 16 or newer, open it once, and install its command-line tools.
2. Open `Stillwater.xcodeproj`. Select the **Stillwater** scheme and **My Mac**.
3. In the Stillwater target's **Signing & Capabilities**, choose your development team. Keep App Sandbox, Hardened Runtime, and Keychain Sharing enabled. The checked-in entitlement declares `$(AppIdentifierPrefix)app.stillwater.passwords`; your signing profile must authorize this group. Only user-selected file access is requested; the app has no network entitlement. The local Swift package includes the pinned libsodium XCFramework, so building needs no package downloads.
4. Press Command-R. For everyday local installation, build Release, locate `Stillwater.app` under Products, reveal it in Finder, and copy it to Applications. Use a consistently signed build for Keychain access. Do not disable Gatekeeper or system integrity protections.
5. For distribution, use a Developer ID signed Release archive, notarize it with Xcode Organizer, staple it, and verify its signature and entitlements. Those release steps require your Apple account and have not been performed here.

Command-line checks from the repository root:

```sh
python3 Scripts/check-source.py
Scripts/check-argon2.sh
swift test --package-path Core
xcodebuild test -project Stillwater.xcodeproj -scheme Stillwater \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
xcodebuild build -project Stillwater.xcodeproj -scheme Stillwater \
  -configuration Release -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

The unsigned Release command is a compile check, not a distributable release. Configure your signing team in Xcode for real Keychain and Touch ID testing. The shared scheme includes app session tests; the Core test suite runs with `swift test`. CI has run these commands successfully on a GitHub macOS runner; see the linked validation run above. `Scripts/generate-project.py` regenerates the checked-in project without XcodeGen or other dependencies.

## Updating after the VaultCore build error

Quit Xcode, download a fresh project ZIP from GitHub, and open `Stillwater.xcodeproj` inside the newly extracted folder. Select Stillwater / My Mac and press Command-R. The corrected Debug settings build for the active Mac architecture, matching the local Swift package; Release keeps universal architecture support. The prior ZIP could try to compile the app for Intel while its package had only an Apple Silicon module. This correction does not change the vault format or storage location.

## Everyday use

The app opens in dark mode with charcoal surfaces and restrained blue accents. Choose **Settings → Appearance** for Dark, Light, or System; the choice is remembered. The main window, settings, and sheets follow this preference.

Create a master password of at least 14 characters; a unique phrase of several unrelated words is recommended. There is no reset. Store this phrase safely outside the app. Use **+** or Command-N to add an account, Command-F to find one, Command-E to edit, and Shift-Command-L to lock. Passwords are hidden until revealed; reveals close after 15 seconds. Copies clear after 30 seconds, or immediately on lock, only when the clipboard is unchanged.

Use the sidebar to organize favorites and folders. Removing a folder keeps its accounts. Deletion requires confirmation. Settings controls the inactivity timeout (1–15 minutes), master password changes, and Touch ID. Touch ID is required for normal unlocking. If it has not been enabled yet, use master-password recovery and enable it in Settings. Choose **Recover with Master Password…** explicitly to recover without a fingerprint; recovery does not disable Touch ID. Changing your master password rotates the vault key, locks the vault, and disables Touch ID; enable it again after unlocking.

## Import

Choose **Vault Actions → Import Password CSV**. Use UTF-8 with a header row, up to 8 MiB, 64 columns, and 10,000 accounts. Match the name and password columns and any optional website, username/email and notes columns. Validate, review the masked preview, and explicitly choose to skip duplicates or keep both. Duplicate identity is name + website + username, trimmed and case-insensitive. Existing entries are never overwritten. Invalid rows block the import. All imported accounts initially have no folder.

The source CSV is plaintext and remains wherever you selected it. The app does not create plaintext exports or temporary CSV copies. Remove or protect that original using your own retention policy; deletion does not guarantee erasure from SSDs or backups.

## Backup and restore

Choose **Vault Actions → Export Encrypted Backup** and keep the `.stillwater` file on a separate safe device/location. Backups are encrypted and contain all account data. Restore from the welcome screen or Vault Actions, select the file, and enter the master password that was active when that backup was made. Restoration replaces the current vault after explicit confirmation; first export a current backup if you need to keep it. There is no merge or cloud sync.

Restoration works without the original Mac or Keychain. Forgotten master passwords cannot be reset. Old backups remain accessible with their old master password after a password change, and may retain deleted accounts. Keep backup history accordingly.

The live vault is `Library/Application Support/Stillwater/Vault.stillwater` inside this app's sandbox container. Back up through the app rather than moving its live file while it is running.

## Security and evidence

Read [Security design](Docs/SECURITY.md), [review findings and test results](Docs/REVIEW.md), and [required Mac verification](Docs/MAC_VALIDATION.md). The app never needs account providers or network access. It cannot protect secrets from malware on an unlocked or compromised Mac, and cannot promise reliable erasure of Swift or framework memory copies.

Dependencies: Apple CryptoKit/Security/LocalAuthentication and libsodium 1.0.22, with its distribution pinned in [DEPENDENCIES.md](Docs/DEPENDENCIES.md). No runtime analytics or external services.
