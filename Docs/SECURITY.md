# Security design — written before implementation

Stillwater is an unaudited, offline password vault for macOS 14+. Use fictional data until the Mac validation checklist and independent review are complete.

## Threat model
Protect a copied vault or backup against offline guessing and modification, and protect a locked session from casual local access. Encrypt all account and folder metadata. No analytics, networking, remote icons, plaintext export, indexing, or third-party crash reporting. File size, format version, KDF costs, random salt, and vault identifier are public. File length leaks approximate content size. An attacker can delete or roll back an entire vault; authenticated encryption cannot detect rollback without external trusted state.

A compromised OS, administrator, keylogger, malicious accessibility software, debugger, or malware operating while unlocked can read secrets. Clipboard consumers may read copied secrets before expiry. Swift String/Data, UI frameworks, and CryptoKit can make copies that cannot be reliably zeroized. Lock removes session references, UI state, and keys; an already running key derivation can retain its input until completion, but a generation token prevents it from reopening a locked session; it cannot promise forensic erasure, prevent swap, or erase earlier system snapshots. Enable FileVault and keep macOS current.

## Key lifecycle and format
Generate a fresh 256-bit vault key with SecRandomCopyBytes. Derive a separate 256-bit wrapping key with Argon2id v1.3 through libsodium 1.0.22 from UTF-8 master password bytes and a unique 16-byte random salt. Store versioned costs; default 64 MiB, three passes, one lane. Accept only bounded costs (64–256 MiB, 3–10 passes, one lane (libsodium’s Argon2id API)) and bounded input before derivation. Benchmark this profile on the target Mac; do not automatically reduce security floors for speed.

Wrap the vault key with AES-256-GCM. Encrypt the entire JSON payload separately with that key. Both use CryptoKit-generated random 96-bit nonces on every seal. Domain-separated authenticated headers bind format, vault ID, salt, and costs. Every successful edit writes a newly encrypted payload atomically. Changing the master password rotates the vault key and creates a fresh salt, wrapping key, and wrapped key; older backups still require their old password. Backups contain only the encrypted envelope and can be restored with the master password on any compatible Mac, without Keychain.

Optional Touch ID stores the random vault key as a data-protection Keychain item gated by SecAccessControl with biometryCurrentSet and WhenUnlockedThisDeviceOnly. Retrieval itself must authorize access; a standalone biometric dialog is not used as proof. Keychain items are scoped by vault ID. Disabling Touch ID or changing the master password removes the item. Re-enrollment invalidates biometric access. Master password remains the fallback. No master password is persisted. There is no reset or recovery key in version 1.

## Persistence and failures
Keep ciphertext in sandbox Application Support, directory mode 0700 and file mode 0600. Write a same-directory exclusive temporary ciphertext file, fsync it, rename atomically over the original, then fsync the directory. On pre-commit failure remove only this operation's temporary file; never remove the original. Keep the previous in-memory state until commit succeeds. Bound reads to 16 MiB, entry counts and field lengths; validate authenticated plaintext schema. Refuse symbolic links and detect unexpected concurrent on-disk changes. Enforce one application instance.

CSV is explicitly plaintext input supplied by the user; parse in memory, bound bytes, rows, and fields, preview masked passwords, require mapping, and mark duplicates for explicit skip or keep-both. Never overwrite existing accounts. No plaintext CSV output or temporary files.

## Guidance and verification status
Requested references: [CryptoKit](https://developer.apple.com/documentation/cryptokit), [Apple biometric Keychain guidance](https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id), [OWASP Password Storage](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html), [Argon2 reference](https://github.com/P-H-C/phc-winner-argon2).
Apple and OWASP web destinations were denied by the environment egress proxy on 2026-10-26. The official OWASP source and Argon2 source can be checked through GitHub. Apple API configuration must be verified on a signed Mac build. Do not equate source review or Linux checks with macOS security validation.

The official OWASP source was retrieved through its GitHub repository on 2026-10-26. It recommends Argon2id with at least 19 MiB, two iterations, one lane; this app uses 64 MiB, three iterations, one lane. The native Mac speed check reports timing without lowering the cost. Linux reference implementation benchmark: 0.149 CPU seconds for this profile; this is not a MacBook benchmark.

Matching libsodium 1.0.22 Linux build passed all 101 upstream tests and the independent Argon2id known-answer comparison. Its selected profile took 0.061 CPU seconds in one measurement; Apple binary behavior and target-Mac latency remain unverified.
