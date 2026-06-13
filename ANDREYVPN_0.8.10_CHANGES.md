# AndreyVPN 0.8.10 — Import Overwrite Fix

## Summary

This release fixes full backup import failure when restoring files that already exist in the target application data directory.

## Changes

- Updated app version to 0.8.10+50.
- Fixed import failure caused by copying `db.sqlite` over an existing file.
- Added overwrite-aware file restore logic.
- Added diagnostics for file overwrite operations and restored file sizes.
- Kept import/export diagnostics enabled.
- No VPN core logic changes.
- No rollback/safe restore redesign yet.

## Files changed

- `pubspec.yaml`
- `appcast.xml`
- `.github/workflows/build-windows-andrey.yml`
- `lib/features/settings/notifier/full_backup_notifier.dart`

## Risk

Medium. The import process now intentionally overwrites existing user data files during restore.

## Test plan

1. Create a full backup.
2. Make a visible change, for example add or remove a test profile.
3. Import the backup.
4. Restart AndreyVPN.
5. Confirm whether profiles/settings returned to the backup state.
6. Send the generated `*_import_diagnostic.log`.
