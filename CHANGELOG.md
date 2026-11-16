# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `--clear-remap` flag to remove a leftover caps lock remap.
- Refuse to start a second instance for the same user; quitting either copy used to remove the caps lock remap for both.

### Fixed

- Keep other `hidutil` key remaps instead of replacing the whole `UserKeyMapping` table on start, quit and `make uninstall`.
- Clear the caps lock remap safely on SIGINT and SIGTERM (no work inside a signal handler), and also when the terminal closes (SIGHUP) or on logout.
- Stop adding ⇧⌃⌥⌘ to every key after a caps lock release was missed (password prompt, lock screen, disabled event tap), and ignore stray releases for double-tap detection.
- Time double taps with a monotonic clock so a system clock change cannot toggle caps lock on a single tap.
- Report `hidutil` failures and exit with an error when the caps lock remap cannot be installed, instead of running without it; a failed caps lock state read no longer forces caps lock on.
- Wait in-process for Accessibility permission instead of exiting, so the LaunchAgent no longer restarts hyperkey every 10 s, flips the caps lock remap and grows the log until permission is granted.
- Re-apply the caps lock remap if macOS drops it when a keyboard connects or after wake.
- A key pressed between two caps lock taps now cancels the double tap, as documented.

### Security

- Sign the binary with the hardened runtime so injected libraries (`DYLD_INSERT_LIBRARIES`) cannot reuse its Accessibility permission.

## [0.1.0] - 2026-11-15

### Added

- Caps lock as hyper key (⇧⌃⌥⌘) while held, via `hidutil` remap to F18 and a HID-level event tap.
- Double-tap caps lock alone to toggle real caps lock (LED included).
- Menu bar item with version and Quit.
- `--version`, `--help` and `--verbose` flags.
- Homebrew formula with `brew services` support.
- Universal (arm64 + x86_64) release builds with SHA256 checksums and build provenance attestation.

[Unreleased]: https://github.com/drosam/hyperkey/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/drosam/hyperkey/releases/tag/v0.1.0
