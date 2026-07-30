# TermVault (iOS)

A native SwiftUI SSH client — host vault, terminal, SFTP browser, key
manager — built to the shape described in the project's iOS spec
(`termiuscloneiosspec.md`). Original code and assets throughout; inspired by
the layout/flow of existing SSH clients, not copied from them.

## Stack

- SwiftUI + Combine, iOS 17+, SwiftData (spec's "or SwiftData if targeting
  iOS 17+" option — avoids hand-authoring a `.xcdatamodeld`)
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT) for the
  terminal emulator
- [Citadel](https://github.com/orlandos-nl/Citadel) (Apache 2.0) for
  SSH/SFTP, built on swift-nio-ssh
- Keychain Services for every secret (host passwords, private keys,
  passphrases) — never SwiftData/UserDefaults/plist
- LocalAuthentication for the Face ID / passcode app lock
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) generates the
  `.xcodeproj` from `project.yml` — there is no checked-in Xcode project,
  so this repo has no macOS-only binary files to diff or merge-conflict on.

## Layout

```
ios/
├── project.yml                 XcodeGen spec: target, SPM deps, Info.plist
└── Sources/App/
    ├── TermVaultApp.swift       App entry, SwiftData container, lock gate
    ├── Models/                  SwiftData models (Host, Identity, Snippet)
    ├── Services/                Keychain, biometric lock, SSH/SFTP, key generation
    ├── ViewModels/               SessionStore, per-screen view models
    ├── Views/                   HostList, HostEditor, Terminal, SFTP, Keychain, Settings
    └── Resources/Assets.xcassets
```

## Building locally (needs macOS + Xcode)

```bash
brew install xcodegen
cd ios
xcodegen generate
open TermVault.xcodeproj
```

Or headless:

```bash
cd ios
xcodegen generate
xcodebuild -project TermVault.xcodeproj -scheme TermVault \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

SwiftTerm and Citadel are resolved via Swift Package Manager the first time
Xcode (or `xcodebuild`) opens the generated project — no manual `pod
install`/`carthage` step.

## What's implemented vs. stubbed

This is an MVP-shaped scaffold, not a store-ready build. Implemented:

- Host CRUD, grouping, search, swipe actions (`Views/HostList`)
- Keychain-backed password storage; SwiftData holds only metadata
- Identity Manager: **real** Ed25519 key generation (proper
  `openssh-key-v1` container) and RSA 4096 generation (via `SecKey`,
  standard PKCS#1 PEM) — see `Services/IdentityKeyGenerator.swift`
- Face ID / passcode app lock, re-locks on backgrounding
- Terminal screen with the extra-keys accessory bar (Esc/Tab/Ctrl/Alt/
  arrows) wired to send raw bytes
- Multi-session tabs via `SessionStore` (swipe between open sessions)
- SFTP browser UI (list/upload/download/rename/delete/new folder)

Deliberately left as TODOs, called out in code comments where they live —
**do not ship without closing these**:

- **Host key verification** (`Services/SSHSessionManager.swift`): currently
  `.acceptAnything()`. Spec section 6 is explicit this must never ship.
  `Services/HostKeyStore.swift` has the TOFU pinning logic ready; it needs
  wiring into whatever host-key-validation hook Citadel exposes in the
  version SwiftPM resolves (this has moved across Citadel releases and
  couldn't be pinned down without a macOS toolchain to check
  `Package.resolved` against).
- **Private-key SSH auth**: Keychain storage/UI is wired end-to-end, but
  `SSHSessionManager.makeAuthenticationMethod` throws
  `privateKeyAuthNotYetWired` for `.privateKey` hosts — parsing Keychain
  PEM into the `NIOSSHPrivateKey` variant Citadel's
  `SSHAuthenticationMethod.privateKey` expects needs the same
  version-check.
- **Terminal stdin writing**: `SSHSessionManager.send(_:hostID:)` casts to
  a local `SSHShellWriting` protocol as a placeholder for whatever
  `requestShell()`'s real return type's write method turns out to be.
- Ctrl/Alt keys in the extra-keys bar toggle visually but don't yet remap
  the next keystroke (needs intercepting `TerminalView`'s key input).
- iCloud sync toggle in Settings is UI-only (no CloudKit container wired).
- Ed25519 key passphrases are stored in the Keychain but the on-disk
  `openssh-key-v1` private section is unencrypted — add bcrypt-pbkdf +
  aes256-ctr before treating passphrase protection as real.

None of this could be verified by actually compiling here — there's no
macOS/Xcode toolchain in this environment. The GitHub Actions workflow
(`.github/workflows/ios-unsigned-ipa.yml`) is where this actually builds,
on a `macos` runner.

## Licensing (About screen)

- SwiftTerm — MIT
- Citadel — Apache 2.0
