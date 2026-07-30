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

This is an MVP-shaped scaffold, not a store-ready build. There's no macOS
toolchain in the environment this was built in, so nothing here has gone
through `xcodebuild` — but the SSH/SFTP/terminal integration code was
checked line-by-line against the actual upstream sources (Citadel 0.12.1,
SwiftTerm 1.15.0, and the `Wellz26/swift-nio-ssh` fork Citadel depends on,
all pulled via `git clone` and read directly) rather than written from
memory, and fixed up where that reading turned up real API mismatches.

Implemented:

- Host CRUD, grouping, search, swipe actions (`Views/HostList`)
- Keychain-backed password storage; SwiftData holds only metadata
- Identity Manager: **real** Ed25519 key generation (proper
  `openssh-key-v1` container) and RSA 4096 generation (via `SecKey`,
  standard PKCS#1 PEM) — see `Services/IdentityKeyGenerator.swift`
- **Real TOFU host key verification** (`Services/TOFUHostKeyValidator.swift`):
  wired into Citadel's actual extension point,
  `SSHHostKeyValidator.custom(_: NIOSSHClientServerAuthenticationDelegate)`.
  Pins the fingerprint on first connect via `HostKeyStore`, hard-fails on a
  later mismatch. This replaces the placeholder `.acceptAnything()` spec
  section 6 says must never ship.
- **Real Ed25519 private-key SSH auth**: Citadel's
  `SSHAuthenticationMethod.ed25519(username:privateKey:)` takes a plain
  swift-crypto `Curve25519.Signing.PrivateKey`, so
  `IdentityKeyGenerator.parseEd25519PrivateKey(pem:)` reverses the
  `openssh-key-v1` container back to the raw 32-byte seed and hands it
  straight to Citadel — no placeholder in this path anymore.
- **Real interactive shell I/O**: `SSHSessionManager` uses Citadel's actual
  `client.withPTY(_:perform:)` (there is no `requestShell()` — that was a
  guess from an earlier pass, corrected after reading `TTY/Client/TTY.swift`
  directly). `perform`'s closure only returns when the session ends, so
  `connect()` runs it inside a long-lived `Task` and stashes the
  `TTYStdinWriter` it hands back for `send(_:hostID:)`/resize.
- Face ID / passcode app lock, re-locks on backgrounding
- Terminal screen with the extra-keys accessory bar (Esc/Tab/Ctrl/Alt/
  arrows) wired to send raw bytes
- Multi-session tabs via `SessionStore` (swipe between open sessions)
- SFTP browser (list/upload/download/rename/delete/new folder), matched
  against Citadel's actual `SFTPClient`/`SFTPFile` (e.g. `listDirectory`
  returns batched `SFTPMessage.Name.components`, not a flat list; file
  mode is a raw POSIX `permissions: UInt32?`, not a `isDirectory` flag or
  a pre-formatted string — both handled in `SFTPService`)

Genuinely left undone, for reasons confirmed against the real API rather
than assumed:

- **RSA private-key SSH auth is not practically wireable through Citadel's
  public API.** `Insecure.RSA.PrivateKey` (`Algorithms/RSA.swift`) has
  exactly two initializers: one taking raw BoringSSL `BIGNUM` pointers
  (`CCryptoBoringSSL` isn't an exposed product, so app code can't reach
  it), and an internal from-scratch generator that's actually a
  Diffie-Hellman-style computation misnamed "RSA" — not something you can
  import a standard PEM into. `SSHSessionManager` throws
  `SSHConnectionError.rsaPrivateKeyAuthUnsupported` with this explanation.
  Use an Ed25519 identity for key-based auth instead.
- Ctrl/Alt keys in the extra-keys bar toggle visually but don't yet remap
  the next keystroke (needs intercepting `TerminalView`'s key input).
- iCloud sync toggle in Settings is UI-only (no CloudKit container wired).
- Ed25519 key passphrases are stored in the Keychain but the on-disk
  `openssh-key-v1` private section is unencrypted — add bcrypt-pbkdf +
  aes256-ctr before treating passphrase protection as real. The parser in
  `IdentityKeyGenerator.parseEd25519PrivateKey` only handles `cipher "none"`
  for the same reason and throws a clear error on an encrypted key.
- The TOFU validator auto-trusts a *new* host key silently (matching
  classic SSH `known_hosts` first-connect behavior) rather than prompting
  the user before trusting it — only a *changed* key hard-fails. A
  confirm-before-trust prompt would need bridging the synchronous
  `EventLoopPromise`-based `validateHostKey` callback to an async UI
  round-trip.

The GitHub Actions workflow (`.github/workflows/ios-unsigned-ipa.yml`) is
where this actually builds, on a `macos` runner — that's the first place
any of this sees a real Swift compiler.

## Licensing (About screen)

- SwiftTerm — MIT
- Citadel — Apache 2.0
