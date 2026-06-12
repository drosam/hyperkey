# hyperkey

Turns caps lock into a hyper key (⇧⌃⌥⌘) on macOS. Single Swift file, no dependencies.

- **Hold caps lock + another key** → that key gets ⇧⌃⌥⌘ stamped onto it (bind hyper combos in apps, skhd, etc.)
- **Tap caps lock alone** → normal caps lock toggle, LED included
- Works on all keyboards, including external ones plugged in later
- Menu bar icon (✦) with a Quit item

## Build

```sh
swiftc -O main.swift -o hyperkey
```

## Run

```sh
./hyperkey
```

Requires Accessibility permission for the terminal you launch it from
(System Settings → Privacy & Security → Accessibility). Without it, the
event tap can't be created and the program exits with instructions.

Quit via the ✦ menu bar icon or Ctrl+C — both restore normal caps lock.

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

The remap is removed on quit, Ctrl+C, and SIGTERM.

## Caveats

- The `hidutil` remap is system-wide but not persistent: a reboot clears it.
- If the process is killed with SIGKILL, the remap stays orphaned (caps lock
  acts as F18 with nothing listening). Fix:

  ```sh
  hidutil property --set '{"UserKeyMapping":[]}'
  ```
