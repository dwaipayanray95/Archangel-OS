# Security policy

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Report it privately with GitHub's private vulnerability reporting:

1. Go to <https://github.com/dwaipayanray95/Project-Archangel/security/advisories/new> (or the repository's **Security** tab → **Report a vulnerability**).
2. Describe what you found, how to reproduce it, and what you think the impact is.
3. Don't include real secrets (tokens, private keys) from a live server.

This is a small personal project, so replies may take a little while. We will do our best to respond promptly, keep you updated, and credit you in the fix if you want.

If private vulnerability reporting is not available for you, open a normal issue that says only "I need to report a security problem privately", with no details, and we will arrange a private channel.

## Supported versions

Only the **latest release** gets security fixes. Please update to the newest app and server program (the app shows an "update available" badge in Settings) before reporting, if you can.

## What counts

Things we especially want to hear about:

- Reaching the Archangel server without a valid tunnel key or token
- Gaining more privileges than a token should give (for example, turning Admin mode on through the API)
- Escaping the Files screen's folder limit
- Leaking keys, tokens or pairing codes
- Problems with update checksum verification

How Archangel is meant to work, and its known limits, are described in [docs/security.md](docs/security.md).
