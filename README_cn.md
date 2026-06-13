# AndreyVPN

AndreyVPN is a Windows portable VPN client.

## Current version

AndreyVPN 0.9.1

## Windows portable storage

User data is stored next to `AndreyVPN.exe` in:

```text
andreyvpn_data/
```

This folder contains profiles, settings, logs, backup state and runtime data.

## Build

Windows builds are produced through GitHub Actions using the `Build Windows AndreyVPN` workflow.

## Updates

Portable builds are distributed through GitHub Releases. The application can update itself through `AndreyVPNUpdater.exe`.

## Notes

Some internal source package names are intentionally left unchanged where they are part of upstream core integration and are not user-facing.
