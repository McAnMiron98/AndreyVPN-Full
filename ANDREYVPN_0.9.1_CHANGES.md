# AndreyVPN 0.9.1 — Visible Branding Cleanup

## Changes

- Updated app version to `0.9.1+62`.
- Cleaned visible upstream branding references from GitHub release message template.
- Cleaned visible upstream support links from GitHub issue templates.
- Removed unused legacy multi-platform GitHub workflows that still referenced upstream release/package metadata.
- Replaced old multi-language upstream README files with compact AndreyVPN README files.
- Replaced old upstream CHANGELOG/HISTORY/CONTRIBUTING/CODE_OF_CONDUCT text with compact AndreyVPN-specific documents.
- Left internal Dart package names, core bindings, generated code, submodule paths, and runtime core integration untouched to avoid breaking build or VPN runtime.

## Risk

Low to medium. This release changes visible project metadata/templates/docs and removes unused legacy workflows. It does not change VPN core logic.

## Test plan

1. Run GitHub Actions Windows build.
2. Confirm the artifact name is `AndreyVPN-0.9.1-windows-portable`.
3. Confirm the release package still contains `AndreyVPN.exe`, `AndreyCli.exe`, and `andrey-core.dll`.
4. Launch the app.
5. Connect VPN and verify traffic works.
