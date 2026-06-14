# AndreyVPN 1.0.1 — JSON Subscription Fallback

## Changes

- Updated app version to 1.0.1+68.
- Added fallback support for JSON-array subscriptions such as Pecan subscription feeds.
- Preserved existing subscription import logic for normal links and standard configs.
- JSON-array subscriptions are converted into VLESS URI subscription lines before the existing parser runs.
- Added support for VLESS TLS, Reality, TCP and XHTTP fields during conversion.
- Added diagnostics log: `andreyvpn_data/logs/andreyvpn_json_subscription.log`.
- No VPN core logic changes.

## Test plan

1. Build Windows release with GitHub Actions.
2. Add a normal existing subscription and confirm it still works.
3. Add the Pecan JSON subscription URL and confirm servers appear.
4. Select one imported server and connect VPN.
5. Check `andreyvpn_data/logs/andreyvpn_json_subscription.log` if import fails.
