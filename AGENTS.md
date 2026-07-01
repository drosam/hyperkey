# AGENTS.md

Guidance for coding agents working in this repository.

## Project

`hyperkey` is a tiny macOS Swift/AppKit menu bar utility. It remaps caps lock to F18 with `hidutil`, intercepts F18 with a HID-level `CGEventTap`, stamps ⇧⌃⌥⌘ onto other key events while held, and toggles real caps lock via IOKit when double-tapped alone.

## Commands

- Build: `make build`
- Run manually: `make build && ./hyperkey`
- Run with verbose key logging: `make build && ./hyperkey --verbose`
- Install LaunchAgent: `make install`
- Uninstall LaunchAgent and clear remap: `make uninstall`
- Clean build artifact: `make clean`

## Workflow

- Read `main.swift` and `Makefile` before changing behavior.
- Keep the project dependency-free and single-file unless explicitly asked.
- Prefer small, focused edits.
- Do not add packages, package managers, or app bundles without approval.
- Do not commit, push, install, uninstall, or launch the app unless asked.
- Preserve user-facing install/accessibility notes in `README.md` when behavior changes.

## Validation

- For code changes, run `make build` when feasible.
- Avoid running long-lived `./hyperkey` in automation; it needs Accessibility permission and owns a global keyboard remap until exit.
- If manual runs leave caps lock mapped to F18, clear it with:

  ```sh
  hidutil property --set '{"UserKeyMapping":[]}'
  ```

## Code notes

- `main.swift` contains all runtime behavior.
- `Makefile` builds, installs to `~/.local/bin/hyperkey`, writes the LaunchAgent, and opens Accessibility settings.
- The binary requires Accessibility permission for whichever executable is launched (`./hyperkey`, installed binary, or terminal when run manually).
- SIGINT, SIGTERM, menu quit, and uninstall clear the `hidutil` remap; SIGKILL cannot.

## Git safety

- `git status`, `git diff`, and `git log` are safe.
- Avoid destructive git commands unless explicitly requested.
- Keep unrelated worktree changes untouched.
