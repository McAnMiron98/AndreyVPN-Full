# AndreyVPN 0.9.4 — Logs Page Actions

## Changed

- Moved diagnostics actions from the Backup page to the main Logs page.
- Replaced the previous live log viewer content with two simple actions:
  - Open logs folder
  - Clear logs
- Kept the unified diagnostics folder at `andreyvpn_data/logs`.

## Removed from Backup page

- Open logs folder action.
- Clear logs action.

## Safety

- No VPN core logic changes.
- No backup/import data format changes.
- No portable storage changes.
