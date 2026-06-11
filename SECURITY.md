# Security Policy

## Supported Version

Security fixes are applied to the latest version on the default branch.

## Reporting A Vulnerability

Please use GitHub's private vulnerability reporting feature for this
repository. Do not open a public issue containing credentials, tokens, session
contents, personal paths, or other sensitive information.

Include:

- A description of the issue and its impact
- Reproduction steps
- The affected files or versions
- A suggested fix, if available

## Credential Handling

This project must:

- Read provider credentials only when required at runtime
- Never print, cache, transmit to third parties, or commit credentials
- Never refresh or rotate provider OAuth tokens
- Keep cached data limited to usage percentages and reset timestamps

If a token is accidentally exposed, revoke it through the relevant provider
and remove it from Git history before publishing any replacement.
