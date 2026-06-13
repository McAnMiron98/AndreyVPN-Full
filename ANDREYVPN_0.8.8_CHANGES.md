# AndreyVPN 0.8.8 — Import Diagnostics

## Summary

This release adds detailed diagnostic logging to the full backup import flow.

## Changes

- Updated app version to `0.8.8+48`.
- Added import diagnostic log generation for full backup restore.
- Import diagnostics now record:
  - selected backup ZIP path and size;
  - target `baseDir`, `workingDir`, and `databaseDir`;
  - temporary restore directory;
  - decoded ZIP entry count;
  - ZIP entry names and sizes;
  - extraction result and extracted file count;
  - manifest presence and content;
  - restored file count for `base`, `working`, and `database` sections.
- Import diagnostic log is saved next to the selected backup ZIP as:
  - `*_import_diagnostic.log`
- Export diagnostic logging is kept unchanged for now.
- No VPN core logic changes.
- No safe restore/rollback redesign yet.
- No Hiddify cleanup changes.

## Risk

Low.

The change only adds diagnostics around the existing import flow. The actual restore strategy is not redesigned yet.
