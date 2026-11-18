# Changelog

All notable changes to FlClash Egress Guard are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The source is now public under the MIT license.

### Added

- Bilingual GitHub repository link in the menu-bar footer and an About window with the app version, MIT license and author profile.
- English and Simplified Chinese interfaces, with a remembered language choice and system-language default (English for non-Chinese systems).
- English README screenshots and bilingual walkthrough GIFs rendered from the app's views without starting protection services.
- User guide in English and Simplified Chinese, with screenshots and illustrations.
- Security policy, code of conduct, feedback guide and issue forms.

## [1.1.0] - 2026-11-16

First public version. Apple silicon, macOS 13 or later.

### Added

- Menu-bar app **FlClash 出网保护** with a status popover and a panel for daily protection, boot protection, restoring the original setup and viewing the log.
- Daily protection with a guided four-step check (核对状态, 接通 FlClash, 启用规则, 验证联网) that ends by loading Google and Douyin through FlClash.
- Kill switch: when FlClash quits or loses its TUN, the public internet locks within about a second, while the local network keeps working.
- Optional boot protection that starts every session locked and shows the menu-bar shield after login.
- One-time authorization, so daily use doesn't ask for a password.
- Release asset `FlClash-Egress-Guard-macOS-arm64.zip`, signed locally and not notarized, SHA-256 `3963ca32748f2b735b9c937aeb9450da2a0ce5d5e1b2fbffe7158b2e2c202315`.

[Unreleased]: https://github.com/madgiraffe1/flclash-egress-guard/releases
[1.1.0]: https://github.com/madgiraffe1/flclash-egress-guard/releases/tag/v1.1.0
