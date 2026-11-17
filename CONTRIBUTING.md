# Contributing

Issues and pull requests are welcome. For larger changes, open an issue first
so the approach can be discussed.

## Project constraints

- No dependencies, no package managers, no app bundle.
- `main.swift` holds runtime glue (event tap, `UserKeyMapping` remap, IOKit, menu bar).
- `HyperKeyState.swift` holds the pure key state machine. Behavior changes
  belong here, with tests.
- `Tests/main.swift` is a tiny assert runner compiled with `swiftc`.

## Requirements

- macOS 14.5 or later to build (the binary runs on macOS 13)
- Xcode Command Line Tools 16 or later for Swift 6 (`xcode-select --install`)

The build uses Swift 6 language mode with warnings as errors, and tests use
the same flags.

## Commands

```sh
make build      # native build -> build/hyperkey
make test       # compile and run unit tests
make universal  # arm64 + x86_64 -> build/hyperkey (needs full Xcode for x86_64 on some setups)
make dist       # universal build + zip + SHA256SUMS.txt in build/
make install    # build, install to ~/.local/bin, load LaunchAgent
make uninstall  # unload LaunchAgent, remove files, clear remap
make clean
```

Run by hand with key logging (grant Accessibility to your terminal):

```sh
make build && build/hyperkey --verbose
```

If a crashed run leaves caps lock mapped to F18:

```sh
hidutil property --set '{"UserKeyMapping":[]}'
```

## Developing while installed via Homebrew

Only one hyperkey may run at a time; a second copy exits with
`hyperkey is already running` (0.1.0 does not check). Stop the
Homebrew service while testing a local build, then start it again.

Quick test:

```sh
brew services stop hyperkey
make test
make build && build/hyperkey --verbose   # Ctrl+C to quit
brew services start hyperkey
```

Use `build/hyperkey`, not `hyperkey`: the bare name runs the Homebrew copy on
your `PATH`.

Trying a change for a few days:

```sh
brew services stop hyperkey
make install       # refuses while the Homebrew service is loaded
# ... use it ...
make uninstall
brew services start hyperkey
```

`pgrep -l hyperkey` shows what is running.

## Local code signing (recommended)

macOS ties Accessibility permission to the binary's code signature. Ad-hoc
builds get a new identity on every build, so permission resets after each
`make install`. A self-signed certificate gives a stable identity:

1. Open Keychain Access -> Keychain Access menu -> Certificate Assistant ->
   Create a Certificate...
2. Name: `hyperkey-dev`, Identity Type: Self Signed Root, Certificate Type:
   Code Signing. Check "Let me override defaults" and set Validity Period to
   3650 days; the default is 365.
3. `make install` now signs with it automatically. Grant Accessibility once.

An expired or duplicate `hyperkey-dev` certificate is skipped and the build
falls back to ad-hoc signing; delete the old one in Keychain Access.

Use another certificate name with `make install SIGN_ID="My Cert"`, or force
ad-hoc with `SIGN_ID=-`. The certificate stays on your machine; never commit
or share its private key.

## Pull requests

- Keep changes small and focused.
- Run `make test` and `make build`.
- Add an entry under `## [Unreleased]` in `CHANGELOG.md` for user-facing changes.
- Update `README.md` when install, permission or behavior changes.

## Releasing (maintainer)

### One-time setup

- GitHub environment `release`: required reviewer (the maintainer) and a
  deployment rule allowing only tags matching `v*`.
- In that environment: variable `TAP_APP_CLIENT_ID` and secret
  `TAP_APP_PRIVATE_KEY` for a GitHub App installed on `drosam/homebrew-tap`
  with Contents read and write. The workflow uses it to bump the formula.
- Settings -> General -> Releases: enable release immutability.
- Settings -> Actions -> General: allow only actions created by GitHub and
  require actions to be pinned to a full-length commit SHA.

### Each release

1. Move `Unreleased` entries to a new `## [X.Y.Z] - YYYY-MM-DD` section in
   `CHANGELOG.md`, point the `[Unreleased]:` link at `vX.Y.Z...HEAD`, add a
   `[X.Y.Z]: .../releases/tag/vX.Y.Z` link, and merge to `main`. The release
   fails without both the section and the link. Pre-release tags
   (`vX.Y.Z-rc.N`) need their own `## [X.Y.Z-rc.N]` section and link; they
   publish a GitHub pre-release and do not bump the Homebrew tap.
2. Check the release build locally: `make dist verify SIGN_ID=- VERSION=X.Y.Z`
   (runs the x86_64 slice, so Apple Silicon needs Rosetta). Then tag and push:
   `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. Approve the `release` environment deployment in GitHub Actions. The
   workflow builds, attests, publishes the release and bumps the Homebrew tap.
4. Update locally: `brew update && brew upgrade hyperkey`,
   `brew services stop hyperkey`, toggle hyperkey off and on in Accessibility,
   then `brew services start hyperkey`. Never change the Accessibility entry
   while hyperkey runs; it can freeze all input.
