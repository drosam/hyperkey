# Security Policy

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub:
**Security -> Report a vulnerability** on
[drosam/hyperkey](https://github.com/drosam/hyperkey/security/advisories/new).

Do not open a public issue for security problems. Expect an initial reply
within a week.

## Scope and threat model

hyperkey installs a HID-level event tap, so it can see every key event while
running. That is why it needs Accessibility permission. By design it:

- never sends anything over the network;
- never writes key events anywhere unless you run it with `--verbose`, which
  prints to stdout the keycodes (not text) of keys pressed while caps lock is
  held;
- adds only a caps lock -> F18 entry to the system-wide `hidutil`
  `UserKeyMapping` table (shared by all users), keeping other entries except an
  existing caps lock mapping, and removes that entry on exit.

The binary is signed with the hardened runtime, so dyld ignores
`DYLD_INSERT_LIBRARIES` and other code cannot be injected into it to reuse its
Accessibility permission.

Relevant reports include anything that breaks these guarantees, a tampered
release artifact, or a weakness in the release pipeline.

## Verifying releases

Each release ships `SHA256SUMS.txt` and a GitHub build provenance attestation:

```sh
shasum -a 256 -c SHA256SUMS.txt
gh attestation verify hyperkey-X.Y.Z.zip --repo drosam/hyperkey
```
