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
  prints keycodes (not text) to stdout;
- changes only the `hidutil` caps lock -> F18 mapping, and clears it on exit.

Relevant reports include anything that breaks these guarantees, a tampered
release artifact, or a weakness in the release pipeline.

## Verifying releases

Each release ships `SHA256SUMS.txt` and a GitHub build provenance attestation:

```sh
shasum -a 256 -c SHA256SUMS.txt
gh attestation verify hyperkey-X.Y.Z.zip --repo drosam/hyperkey
```
