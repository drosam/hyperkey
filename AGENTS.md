# AGENTS.md

Guidance for coding agents working in this repository.

## Project

`hyperkey` is a tiny macOS Swift/AppKit menu bar utility. It remaps caps lock to F18 with `hidutil`, intercepts F18 with a HID-level `CGEventTap`, stamps ⇧⌃⌥⌘ onto other key events while held, and toggles real caps lock via IOKit when double-tapped alone. Public repo, distributed via the `drosam/homebrew-tap` formula and GitHub Releases.

## Commands

- Build (native): `make build` -> `build/hyperkey`
- Unit tests: `make test`
- Universal build: `make universal` (x86_64 may need full Xcode)
- Release archive: `make dist` -> `build/hyperkey-$(VERSION).zip` + `build/SHA256SUMS.txt`
- Run manually: `make build && build/hyperkey`
- Run with verbose key logging: `make build && build/hyperkey --verbose`
- Install LaunchAgent: `make install`
- Uninstall LaunchAgent and clear remap: `make uninstall`
- Clean: `make clean`

## Layout

- `main.swift`: runtime glue (CLI flags, `hidutil`, event tap, IOKit, menu bar).
- `HyperKeyState.swift`: pure key state machine. All hold/tap/double-tap logic lives here.
- `Tests/main.swift`: dependency-free assert runner for the state machine.
- `Makefile`: build, sign, test, dist, install/uninstall LaunchAgent. Version comes from `git describe` or `VERSION=`.
- `.github/workflows/ci.yml`: tests, universal build checks, gitleaks.
- `.github/workflows/release.yml`: on `v*` tag, builds, then (after `release` environment approval) attests, publishes the GitHub release and bumps the tap formula.

## Workflow

- Read `main.swift`, `HyperKeyState.swift` and `Makefile` before changing behavior.
- Keep the project dependency-free: no packages, package managers or app bundles without approval.
- Behavior changes go in `HyperKeyState.swift` with tests in `Tests/main.swift`.
- Prefer small, focused edits.
- Do not commit, push, tag, install, uninstall, or launch the app unless asked.
- Keep `README.md`, `CONTRIBUTING.md`, `SECURITY.md` and `CHANGELOG.md` (`Unreleased`) current when user-facing behavior changes.
- Pin GitHub Actions by full commit SHA with a version comment; keep workflow permissions least-privilege.

## Validation

- For code changes, run `make test` and `make build`.
- Avoid running long-lived `build/hyperkey` in automation; it needs Accessibility permission and owns a global keyboard remap until exit. `--version` and `--help` exit before touching the remap.
- If manual runs leave caps lock mapped to F18, clear it with:

  ```sh
  hidutil property --set '{"UserKeyMapping":[]}'
  ```

## Code notes

- Accessibility permission is tied to the binary's code signature. `make build` signs with the `SIGN_ID` keychain identity (default `hyperkey-dev`) when present, else ad-hoc. Releases are ad-hoc (`SIGN_ID=-`); no signing secrets exist in CI.
- SIGINT, SIGTERM, menu quit, and uninstall clear the `hidutil` remap; SIGKILL cannot.
- Minimum macOS is 13 (`MACOS_MIN` in `Makefile`).

## Git safety

- `git status`, `git diff`, and `git log` are safe.
- Avoid destructive git commands unless explicitly requested.
- Keep unrelated worktree changes untouched.
