# AndreyVPN 0.4

Changes:

- Version updated to 0.4.0.
- Added AndreyVPN update checker via GitHub Releases.
- Update source: https://github.com/McAnMiron98/AndreyVPN-Full/releases
- Removed dependency on Hiddify release/update endpoints for update checks.
- The update dialog opens the matching AndreyVPN GitHub Release page.
- VPN logic was not changed.

Release workflow for future updates:

1. Build a new version with GitHub Actions.
2. Create a GitHub Release with tag like `v0.5.0`.
3. Attach the generated Windows portable ZIP to the Release.
4. Older AndreyVPN versions will detect the Release and offer to open it for update.
