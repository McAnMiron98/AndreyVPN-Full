# AndreyVPN 0.5.6

- Fixed Windows updater launcher command.
- Replaced fragile `cmd /c start ...` call with direct detached launch of the generated updater `.cmd` file.
- Keeps updater diagnostics logs in `%LOCALAPPDATA%\AndreyVPN`.
- VPN logic unchanged.
