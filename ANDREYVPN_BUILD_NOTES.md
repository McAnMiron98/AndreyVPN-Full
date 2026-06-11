# AndreyVPN 0.1 Full Source

Это полный исходный код AndreyVPN 4.1.1 с минимальным ребрендингом под AndreyVPN.

Что изменено:

- Windows binary name: `AndreyVPN.exe`
- Windows window title: `AndreyVPN`
- Windows mutex / single instance title: `AndreyVPN`
- `Constants.appName`: `AndreyVPN`
- `common.appTitle` в переводах: `AndreyVPN`
- Windows packaging display name: `AndreyVPN`
- Добавлен отдельный workflow: `.github/workflows/build-windows-andrey.yml`

Что НЕ менялось:

- VPN-логика
- hiddify-core
- sing-box / core API
- структура проекта
- платформенные папки Android/iOS/Linux/macOS
- оригинальные workflow AndreyVPN сохранены

Рекомендуемый workflow для сборки:

`Actions → Build Windows AndreyVPN`

Артефакт:

`AndreyVPN-windows-portable`
