# AndreyVPN 0.8.5 — Backup Export Diagnostics

## Changes

- Updated app version to `0.8.5+45`.
- Added diagnostic logging to full backup export.
- The export process now records detected directories, copied files, skipped files, staging file count, zip size, and selected output path.
- A diagnostic log is saved next to the exported backup ZIP.
- The diagnostic log is also added into the staging folder before ZIP creation.

## Not changed

- No VPN core logic changes.
- No routing changes.
- No profile database schema changes.
- No import/restore redesign yet.
- No Hiddify cleanup/renaming.

## Goal

This version is intended to identify why the current backup ZIP is empty before implementing the final export/import redesign.

## Risk

Low. Export diagnostics only.
