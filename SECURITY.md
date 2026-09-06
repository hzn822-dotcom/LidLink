# Security Policy

LidLink installs a small root-owned LaunchDaemon because changing the lid-sleep policy requires administrator privileges.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting / security advisory feature when it is available for this repository. Do not include passwords, tokens, personal data, or other secrets in a public issue.

## Trust and distribution

- Review the helper source in `Resources/lidlink-helper.sh` before installing it.
- Prefer building from source or using a release signed by a trusted Developer ID.
- Never disable Gatekeeper globally to run LidLink.
