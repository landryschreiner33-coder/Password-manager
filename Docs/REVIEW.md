# Implementation review and validation record

Review performed during development on 2026-10-26. This is self-review, not an independent audit.

## Findings addressed

- Replaced the initial old reference Argon2 runtime dependency with maintained libsodium 1.0.22. Retained reference vectors only as a test fixture; added a cross-implementation KDF known-answer test.
- Password changes now rotate the random vault key as well as salt/wrapping key, revoke biometric access, and lock. An old backup's recovered key cannot decrypt subsequent new vault payloads. Old backups remain readable with their original password.
- In-flight unlock and password-change results use a session generation token, preventing a completed background operation from reopening an explicitly locked session. LAContext is invalidated on lock. Already-running KDF memory is released when its computation returns; Swift memory zeroization is not guaranteed.
- SwiftUI detail/editor/import state is scoped to the unlocked root. Lock removes the root and clears settings password inputs. Reveal has a 15-second deadline. Explicit lock also clears this app's current clipboard item.
- Clipboard writes use `prepareForNewContents(with: .currentHostOnly)` plus concealed/transient markers. Clearing compares the pasteboard change count, so later user copies survive.
- Storage uses exclusive 0600 ciphertext temp files, fsync, same-directory rename, bounded non-symlink reads, and an expected-ciphertext digest. Failed pre-commit writes preserve the original. Settings carry only idle duration and a biometric-enabled hint; the hint does not authorize unlock.
- All KDF parameters, envelope sizes, schema fields and counts are checked before expensive or unbounded processing. Header information is authenticated with separate key/payload domains. Password fields never enter logs or search.
- CSV mapping must use distinct columns, rejects malformed quoting and invalid/oversized rows, and imports only after an explicit preview and duplicate choice. Duplicate handling never updates an existing record.
- Restore authenticates the entire backup before replacing the current vault. Damaged current envelopes can be replaced with an authenticated backup. No original Keychain item is required.
- First-run creation checks password confirmation inside the action as well as disabling the button, so Return cannot bypass confirmation. Lock changes a view epoch even while already locked, removing partially entered master passwords and any locked-screen restore sheet.
- Source review found and corrected a non-optional sidebar selection binding that would not match SwiftUI's List API. The corrected app subsequently passed Swift compilation on the GitHub macOS runner (see the update below).

## Checks executed here

- Matching libsodium 1.0.22 source release built on Linux: 101 upstream tests passed, 0 skipped, 0 failed, 0 errors. Its Argon2id output matched the independent PHC reference vector. The 64 MiB/three-pass/one-lane profile measured 0.061 CPU seconds in one Linux run. This validates the Linux source build, not the vendored Apple binary.
- Vendored PHC reference test-fixture C implementation compiled with GCC, `ARGON2_NO_THREADS`, portable reference implementation.
- Upstream test harness: 24 hash/verification vectors across Argon2i v1.0, Argon2i v1.3, Argon2id v1.3, plus 13 error/encoding checks; all 37 printed PASS and process exited 0. Large-RAM vectors behind `TEST_LARGE_RAM` were not enabled.
- Argon2id v1.3 profile benchmark (64 MiB, three passes, one lane): approximately 0.149 CPU seconds in one Linux measurement. No Mac timings measured.
- All Swift files parsed using tree-sitter; no syntax error nodes. This is not a compiler or type check.
- Vendored-file SHA-256 comparison with pinned upstream files, plist/scheme parsing, minimal-entitlement assertion, deterministic project regeneration and reference checks passed.

## Not executed; release gates

The local authoring machine has no Swift compiler or Xcode. Subsequent GitHub macOS validation successfully completed the Core test command, app build/session-test command, and Release build. The suites define 13 Core XCTest cases and 3 app XCTest cases; the public job page confirms successful steps, but individual result-bundle counts were not independently downloaded. Actual UI behavior, Accessibility, hardware Keychain enforcement, sleep/screen-lock notifications, clipboard propagation across devices, cross-device backup restoration, power-loss behavior and distribution signing remain unverified. No notarized installer is delivered.

Apple documentation URLs were denied by the network proxy. OWASP's official source was retrieved from GitHub. Verify current Apple API guidance and the exact Keychain/clipboard/lock configuration in a signed Mac build. The app uses maintained libsodium 1.0.22 from the pinned Swift distribution; the older PHC code is retained only as an independent test fixture. The Apple framework now compiles and links in the Mac validation workflow; independent artifact provenance/rebuild review remains a release gate (see DEPENDENCIES.md).

Storage's digest comparison detects ordinary accidental concurrent changes; it is not an interprocess transaction lock or a defense against an adversarial process changing files between comparison and rename. The app prohibits ordinary duplicate instances via Info.plist. An actively compromised Mac is outside the threat model. Directory fsync is best-effort after the rename commit; do not treat it as a power-loss guarantee on every filesystem.

Complete [MAC_VALIDATION.md](MAC_VALIDATION.md) and independent security review before using real passwords. Do not remove assertions or disable verification to make these gates pass.

## Appearance revision

Dark appearance now defaults on, with persistent Dark/Light/System selection shared by the app and settings. Added adaptive opaque charcoal surfaces, contrast-aware card borders, a visible search focus outline, compact native list rows, clearer detail actions, and username copying through the existing sensitive clipboard service. Native controls and list selection retain keyboard and accessibility behavior. Updated project registration and re-ran Swift syntax parsing plus project/dependency checks successfully. Visual appearance, VoiceOver and native theme propagation still require hands-on Mac checks; the supplied illustration is not an app capture.

## Mac build correction — 2026-10-27

The initial app build failed because it requested `VaultCore` for `x86_64-apple-macos` while the package build had produced only `arm64-apple-macos`. Set project Debug `ONLY_ACTIVE_ARCH=YES` to match SwiftPM and the selected Mac. Release explicitly retains `ONLY_ACTIVE_ARCH=NO`. Also removed invalid remote-package-reference fields from local product dependencies and explicitly discarded the return value of key-buffer clearing to resolve its warning. Static project checks now reject both configuration regressions.

[GitHub macOS workflow run](https://github.com/landryschreiner33-coder/Password-manager/actions/runs/40522887680), commit `847870f`, completed successfully: dependency verification, upstream Argon2 vectors, Core crypto/storage tests, app compilation and session tests, and Release build. Compiler failures are now surfaced as run annotations while preserving `xcodebuild`'s exit status. These are automated build/test results, not an independent security audit or hardware Touch ID certification.
