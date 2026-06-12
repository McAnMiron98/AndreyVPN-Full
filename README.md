# AndreyVPN

Custom Windows VPN client based on the AndreyVPN open-source project.

## Current version

AndreyVPN 0.8.0

## Build

Windows builds are produced through GitHub Actions using the `Build Windows AndreyVPN` workflow.

## Updates

Portable builds are distributed through GitHub Releases. The application can check for updates and update itself through the external `AndreyVPNUpdater.exe`.

## Notes

Some internal package names and core binary names may still contain `andreyvpn` because they are part of the upstream codebase and VPN core integration. They are intentionally left unchanged to avoid breaking the build.
