# hyperkey

Turns caps lock into a hyper key (⇧⌃⌥⌘) on macOS. Single Swift file, no dependencies.

- **Hold caps lock + another key** → that key gets ⇧⌃⌥⌘ stamped onto it (bind hyper combos in apps, skhd, etc.)
- **Tap caps lock alone** → normal caps lock toggle, LED included
- Works on all keyboards, including external ones plugged in later
- Menu bar icon (✦) with a Quit item

## Requirements

- macOS with Swift available (`swiftc`)
- Accessibility permission for the binary that runs `hyperkey`

## Install

```sh
make install
```

Builds the binary, copies it to `~/.local/bin/hyperkey`, and registers a
LaunchAgent (`com.drosam.hyperkey`) that starts it at login and keeps it
running — no terminal needed.

On first launch macOS prompts for Accessibility permission for the binary
itself (System Settings → Privacy & Security → Accessibility). Until granted,
the process exits and launchd retries every ~10 s; once granted it comes up
on its own. After reinstalling a rebuilt binary you may need to toggle the
permission off and on again, since the binary's hash changed.

Logs go to `~/Library/Logs/hyperkey.log` (quiet by default; pass `--verbose`
for per-key logging when running by hand).

```sh
make uninstall   # stop, remove binary + LaunchAgent, restore caps lock
```

## Run manually

```sh
make build && ./hyperkey
```

Requires Accessibility permission for the terminal you launch it from.

Quit via the ✦ menu bar icon or Ctrl+C — both restore normal caps lock.
(When installed, quitting via the menu keeps it stopped until next login;
restart early with `launchctl kickstart gui/$(id -u)/com.drosam.hyperkey`.)

For debug logging:

```sh
make build && ./hyperkey --verbose
```

## Development

Common commands:

```sh
make build      # compile ./hyperkey
make clean      # remove ./hyperkey
make install    # build, install, and load LaunchAgent
make uninstall  # unload LaunchAgent, remove install files, clear remap
```

The project intentionally stays small: `main.swift` contains the app, and the
`Makefile` contains build/install lifecycle. Keep README install and permission
notes current when user-facing behavior changes.

## How it works

Caps lock's toggle (state + LED) happens inside the HID driver, below any
event tap, so swallowing its events doesn't neutralize it. Instead:

1. `hidutil` remaps caps lock → F18 in the driver itself (`UserKeyMapping`),
   so caps lock never toggles and the key arrives as plain F18 key events.
2. A `CGEventTap` at the HID level intercepts F18: while it's held, a flag
   is set and ⇧⌃⌥⌘ is stamped onto every other key event.
3. If F18 is released without any other key pressed in between, the caps
   lock state is flipped directly through IOKit
   (`IOHIDSetModifierLockState`), since it can't be toggled by posting events.

The remap is removed on quit, Ctrl+C, SIGTERM, uninstall, and normal app exit.

## Caveats

- The `hidutil` remap is system-wide but not persistent: a reboot clears it.
- If the process is killed with SIGKILL, the remap stays orphaned (caps lock
  acts as F18 with nothing listening). Fix:

  ```sh
  hidutil property --set '{"UserKeyMapping":[]}'
  ```
