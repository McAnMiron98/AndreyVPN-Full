# AndreyVPN 0.5.2 — Auto Updater Fix

Changes:
- Bumped version to 0.5.2.
- Improved Windows portable auto-updater.
- Added persistent updater log: `%LOCALAPPDATA%\\AndreyVPN\\AndreyVPN-update.log`.
- Added support for direct portable ZIP, nested GitHub artifact ZIP, and ZIPs with an inner folder.
- Stops helper processes that may keep files locked before replacing files.
- Restarts `AndreyVPN.exe` from the updated application directory.
- VPN logic was not changed.
