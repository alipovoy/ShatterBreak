# Security Policy

## Supported versions

ShatterBreak is an actively developed project. Security fixes are applied to the
latest released version only. Please make sure you are running the most recent
release before reporting an issue.

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
discussions, or pull requests.**

Instead, use GitHub's private vulnerability reporting:

1. Go to the [Security tab](https://github.com/alipovoy/ShatterBreak/security) of
   this repository.
2. Click **Report a vulnerability** to open a private advisory.
3. Describe the issue with as much detail as possible.

A good report includes:

* the affected version (see the menu bar **About** / Preferences for the build),
* a description of the vulnerability and its potential impact,
* step-by-step instructions to reproduce it,
* any proof-of-concept code, configuration, or screenshots, and
* any suggested mitigation, if you have one.

## What to expect

* We aim to acknowledge new reports within **7 days**.
* We will keep you informed as we investigate and work on a fix.
* Once a fix is released, we are happy to credit you in the advisory unless you
  prefer to remain anonymous.

## Scope and distribution note

ShatterBreak is distributed as an ad-hoc–signed macOS app and is **not** notarized
or signed with an Apple Developer ID. Users remove the Gatekeeper quarantine
attribute manually after download (see the README). Reports about the absence of
notarization or Developer ID signing are out of scope, as this is an intentional
distribution decision. Please do report any issue that could compromise a user's
system, data, or privacy beyond that.

Thank you for helping keep ShatterBreak and its users safe.
