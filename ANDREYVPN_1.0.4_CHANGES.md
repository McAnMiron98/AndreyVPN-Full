# AndreyVPN 1.0.4 — Tray Server Switch

## Changes

- Updated app version to 1.0.4+71.
- Added tray menu action for connected VPN state: `Сменить сервер`.
- Tray server switch menu lists servers from the current active subscription.
- Tray server list shows server name and ping.
- Tray server list is sorted by ping from lowest to highest.
- Unknown/unavailable ping servers are shown at the bottom.
- The currently selected server is marked with a checked menu item.
- Excluded `lowest` and `balance` balancers from the tray server switch list.
- No VPN core logic changes.

## Risk

Medium. This change integrates tray menu actions with existing proxy selection logic.

## Test plan

1. Build Windows release through GitHub Actions.
2. Launch AndreyVPN.
3. Connect VPN.
4. Right-click tray icon.
5. Check that `Сменить сервер` appears only while connected.
6. Check that the server list contains current active subscription servers and excludes `lowest` / `balance`.
7. Check that servers are sorted by ping.
8. Select another server from tray.
9. Confirm VPN remains connected and traffic uses the newly selected server.
