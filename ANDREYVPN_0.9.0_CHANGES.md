# AndreyVPN 0.9.0 — Core Binary Rename

## Изменения

- Updated app version to 0.9.0+61.
- Renamed bundled Windows core DLL in the release output:
  - `hiddify-core.dll` → `andrey-core.dll`
- Renamed bundled Windows CLI binary in the release output:
  - `upstreamCli.exe` → `AndreyCli.exe`
- Updated Windows native DLL loader to open `andrey-core.dll`.
- Updated Windows CMake install rules for renamed binaries.
- Updated appcast and Windows portable GitHub artifact naming to 0.9.0.
- No VPN protocol/core logic changes.
- Internal source package/module names are not renamed in this release.

## Risk

Medium. If `andrey-core.dll` is not copied correctly or the loader cannot find it, VPN connection may fail.
