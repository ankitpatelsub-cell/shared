# Third-Party Notices

## Termux terminal-emulator (Apache License 2.0)

`app/src/main/java/com/termux/terminal/*.java` and
`app/src/main/java/com/termux/view/TerminalRenderer.java` are vendored from
the `terminal-emulator` and `terminal-view` modules of
[termux/termux-app](https://github.com/termux/termux-app), which — unlike
the rest of that repository (GPLv3) — are released under the
**Apache License, Version 2.0**, per that project's own `LICENSE.md`:

> [Terminal Emulator for Android](https://github.com/jackpal/Android-Terminal-Emulator)
> code is used which is released under Apache 2.0 license. Check
> `terminal-view` and `terminal-emulator` libraries.

Only the pure-Java VT100/xterm emulation engine and Canvas renderer were
taken — not `TerminalSession.java`/`JNI.java`, which spawn a local shell
via native (JNI) code. TermVault drives the terminal from an SSH channel
instead, so that local-process-spawning path isn't used and no native
build step is needed.

One file was modified: `TerminalSessionClient.java` had its
`TerminalSession`-typed methods removed, since those are only ever called
*by* `TerminalSession` (which this app doesn't construct) — verified by
checking every `mClient.*`/`client.*` call site in `TerminalEmulator.java`
and `Logger.java` before trimming. See the file's own doc comment.

```
Copyright (c) 2019, Fredrik Fornwall (termux/termux-app contributors)
Copyright (c) Jack Palevich (original Android Terminal Emulator)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

## sshj (Apache License 2.0)

`com.hierynomus:sshj` — SSH/SFTP client. https://github.com/hierynomus/sshj

## Bouncy Castle (MIT-style license)

`org.bouncycastle:bcprov-jdk18on`, `org.bouncycastle:bcpkix-jdk18on` — used
by sshj and by `IdentityKeyGenerator` for SSH key generation.
