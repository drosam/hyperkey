# hyperkey

> Turn caps lock into a hyper key (⇧⌃⌥⌘) on macOS. Tiny, native, no dependencies.

Hold caps lock and press any key to send it with ⇧⌃⌥⌘, a modifier combo no app
uses by default, so you get a whole free layer for shortcuts (Raycast,
skhd, Hammerspoon, app shortcuts, ...). Double-tap caps lock to get normal
caps lock back.

## Why hyperkey

A hyper key usually comes bundled inside a much bigger tool:

- **Raycast** - a full launcher; the hyper key is one setting among hundreds.
- **Karabiner-Elements** - a powerful remapping engine with a virtual keyboard
  driver and a background daemon.
- **BetterTouchTool** - a paid suite for gestures, mouse, Touch Bar and keyboard.
- **Hammerspoon** - a Lua automation framework you script yourself.

They are great if you already use them for everything else. If all you want is
caps lock as a hyper key, they are a lot to install, run and grant permissions
to. hyperkey does that one job and nothing more: a single ~170 KB binary, no
driver, no configuration, no network access, and source short enough to read in
a few minutes.

## Highlights

- **Hold caps lock + key** -> that key with ⇧⌃⌥⌘.
- **Double-tap caps lock alone** -> real caps lock toggle, LED included.
- **Works on every keyboard**, including external ones plugged in later.
- **Invisible:** menu bar icon (✦) with version and Quit, no Dock icon, no window.
- **Small and auditable:** a few hundred lines of Swift, no network access, no dependencies.

## Install

Requires macOS 13 or later. Universal binary (Apple Silicon and Intel).

### Homebrew (recommended)

```sh
brew install drosam/tap/hyperkey
brew services start hyperkey
```

`brew services` starts hyperkey now and at every login via a LaunchAgent.
It appears under System Settings -> General -> Login Items & Extensions ->
**Allow in the Background**, not under Open at Login.

Update with `brew upgrade hyperkey`, then re-enable Accessibility (see below).

### GitHub release download

Download `hyperkey-X.Y.Z.zip` and `SHA256SUMS.txt` from the
[latest release](https://github.com/drosam/hyperkey/releases/latest), then verify:

```sh
shasum -a 256 -c SHA256SUMS.txt
gh attestation verify hyperkey-X.Y.Z.zip --repo drosam/hyperkey
```

The attestation proves the zip was built by this repo's release workflow.
Unzip and put `hyperkey` somewhere on your `PATH`. A browser download is
quarantined by Gatekeeper; clear it with `xattr -d com.apple.quarantine hyperkey`
after verifying.

### Build from source

```sh
git clone https://github.com/drosam/hyperkey.git
cd hyperkey
make install
```

Requires Xcode Command Line Tools (`xcode-select --install`). This builds
`build/hyperkey`, installs it to `~/.local/bin/hyperkey` and loads a
LaunchAgent (`com.drosam.hyperkey`) that starts it at login. Do not use this
and `brew services` at the same time; `make install` refuses if the brew
service is loaded. See [CONTRIBUTING.md](CONTRIBUTING.md) for local code
signing so permission survives rebuilds.

## Accessibility permission

hyperkey uses a keyboard event tap, so macOS requires Accessibility
permission for the hyperkey binary:

System Settings -> Privacy & Security -> Accessibility -> enable `hyperkey`.

Until granted, hyperkey waits without remapping caps lock and checks again
every 2 s; once granted it starts on its own.

**After every upgrade or rebuild**, macOS sees a new binary. If hyperkey
stops reacting, quit it from the ✦ menu, remove it from the Accessibility
list (or toggle it off and on), then restart it:

```sh
brew services restart hyperkey                        # Homebrew
launchctl kickstart -k gui/$(id -u)/com.drosam.hyperkey  # make install
```

Always quit hyperkey before changing its Accessibility entry. Revoking the
permission while it runs can freeze keyboard and mouse input until reboot.

Release builds are ad-hoc signed (no paid Apple Developer ID), which is why
the grant does not carry over between versions.

## Usage

```sh
hyperkey            # run in the foreground
hyperkey --verbose  # log keycodes (not text) for debugging
hyperkey --version
hyperkey --help
hyperkey --clear-remap  # remove a leftover caps lock remap and exit
```

Quit from the ✦ menu or with Ctrl+C. Both restore normal caps lock. Under
`brew services` or `make install`, quitting from the menu keeps it stopped
until the next login or a restart command above.

## How it works

Caps lock's toggle (state + LED) happens inside the HID driver, below any
event tap, so swallowing its events doesn't neutralize it. Instead:

1. `hidutil` remaps caps lock -> F18 in the driver itself (`UserKeyMapping`),
   so caps lock never toggles and the key arrives as plain F18 key events.
2. A `CGEventTap` at the HID level intercepts F18: while it's held, ⇧⌃⌥⌘ is
   stamped onto every other key event.
3. If F18 is double-tapped without any other key in between, the caps lock
   state is flipped directly through IOKit (`IOHIDSetModifierLockState`),
   since it can't be toggled by posting events.

The `UserKeyMapping` table is system-wide and shared by all users on the Mac.
hyperkey adds its caps lock entry to it and keeps your other `hidutil`
remaps, but replaces any existing caps lock mapping.

The remap is removed on quit, Ctrl+C, SIGTERM (including `brew services stop`),
closing the terminal (SIGHUP), logout, and `make uninstall`.

## Troubleshooting

**`Refusing to load formula drosam/tap/hyperkey from untrusted tap`.** Homebrew 6
only loads third-party taps you trust. Run `brew trust drosam/tap`, then retry.

**hyperkey does not react.** Check Accessibility permission (see above).
Logs: `$(brew --prefix)/var/log/hyperkey.log` (Homebrew) or
`~/Library/Logs/hyperkey.log` (`make install`).

**Caps lock does nothing at all.** hyperkey was killed with SIGKILL or
crashed and left the remap behind. Clear it:

```sh
hyperkey --clear-remap
```

With hyperkey already uninstalled, use
`hidutil property --set '{"UserKeyMapping":[]}'`, which clears all `hidutil`
remaps.

**Shortcuts fire twice or behave oddly.** Make sure only one hyperkey runs
(`pgrep -l hyperkey`) and that no other remapper (Karabiner-Elements, etc.)
also maps caps lock.

The `hidutil` remap is not persistent: a reboot clears it, and hyperkey sets
it again at launch.

## Uninstall

```sh
brew services stop hyperkey && brew uninstall hyperkey   # Homebrew
make uninstall                                           # source install
```

Then remove hyperkey from the Accessibility list.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).
Report security issues privately as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © David Rosa Moncayo
