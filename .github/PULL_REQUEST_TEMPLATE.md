## What and why

<!-- What does this change, and why? -->

## How I tested it

<!-- macOS version, Mac chip, FlClash version, and what you ran or clicked. -->

## Checklist

- [ ] `sh app/build.sh "/tmp/FlClash 出网保护.app"` builds and the signature verifies.
- [ ] The Python and shell syntax checks in [docs/DEVELOPMENT.md](https://github.com/madgiraffe1/flclash-egress-guard/blob/main/docs/DEVELOPMENT.md#quick-checks) pass.
- [ ] Firewall or helper changes: I tested turning protection on, the lock when FlClash quits, reconnecting, and **解除全部保护** / `disable` / `rollback`.
- [ ] User-facing changes are reflected in **both** `README.md` and `README.zh-CN.md`, and in `CHANGELOG.md` under *Unreleased*.
- [ ] UI changes: screenshots regenerated with `sh docs/tools/render-screenshots.sh`.
- [ ] No personal data (node addresses, subscription links, IPs, user names, home-folder paths) in code, logs, screenshots or this description.
