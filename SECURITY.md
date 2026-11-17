# Security Policy

FlClash Egress Guard changes your Mac's firewall and installs a privileged helper, so security reports are very welcome. 中文报告同样欢迎。

## Supported versions

| Version | Supported |
| --- | :---: |
| 1.1.x (latest release) | ✅ |
| Older versions | ❌ |

## Reporting a vulnerability

**Please don't open a public issue.** Report privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**.

Please include:

- the app version, macOS version, Mac chip and FlClash version;
- what you did, what happened and what you expected;
- the impact as you see it.

Remove personal data first: node or server addresses, subscription links, real IP addresses, Wi-Fi names and user names.

Reports are handled on a best-effort basis. Unless you'd rather stay anonymous, you'll be credited when the fix is released.

## Scope

In scope, for example:

- traffic reaching the public internet outside FlClash while the app shows **已开启** (*On*) or **公网已锁住** (*Internet locked*);
- another user, an unapproved program or a non-admin process changing the firewall through the app's helper;
- privilege escalation through the app, its helper or its boot service;
- personal data, such as addresses, showing up in the app's log or interface.

Out of scope (known limitations):

- software or people that already have administrator rights, who can change the firewall directly;
- DNS queries sent to a resolver on your local network, which are allowed by design;
- traffic in the first moments of startup, before the firewall has loaded its rules;
- vulnerabilities in FlClash or mihomo themselves; please report those to their projects.

## Good to know

- Your administrator password is only typed into macOS's own dialog; the app never handles it.
- The helper only works for the user who authorized it and for the exact copy of the app that was approved, and it only performs a fixed set of protection actions.
- The app never removes or overrides other software's firewall rules.
- The log contains only times, check names and pass/fail.
- Releases are signed locally and not notarized. Download them only from the official release page and compare the SHA-256 shown there: `shasum -a 256 FlClash-Egress-Guard-macOS-arm64.zip`.
