# AndreyVPN 0.8.6 — ZIP Export Fix

## Changes

- Updated app version to `0.8.6+46`.
- Fixed full backup ZIP creation.
- Replaced `ZipFileEncoder.addDirectory(...)` with explicit recursive file collection and manual ZIP archive creation.
- Added diagnostics for:
  - discovered ZIP source files;
  - each file added to ZIP;
  - written ZIP entry count;
  - decoded ZIP entry count after creation.
- Kept backup export diagnostics introduced in 0.8.5.

## Not changed

- VPN/core logic was not changed.
- Profile logic was not changed.
- Import/restore logic was not redesigned yet.
- Hiddify internal naming was not cleaned up.

## Risk

Low. The change is limited to backup ZIP packaging.
