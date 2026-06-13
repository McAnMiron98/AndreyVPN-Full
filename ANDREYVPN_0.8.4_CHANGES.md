# AndreyVPN 0.8.4 — Appcast & Windows Build Artifact Fixes

## Что изменено

- Поднята версия приложения с `0.8.3+43` до `0.8.4+44` в `pubspec.yaml`.
- Исправлен `appcast.xml`:
  - удалены старые записи `0.13.6`;
  - удалены ссылки на релизы `hiddify/hiddify-app`;
  - добавлена корректная Windows portable-запись для AndreyVPN `0.8.4`.
- Исправлен Windows GitHub Actions workflow:
  - имя portable-архива обновлено с `AndreyVPN-0.8.0-windows-portable.zip` на `AndreyVPN-0.8.4-windows-portable.zip`;
  - имя GitHub Actions artifact обновлено с `AndreyVPN-0.8.0-windows-portable` на `AndreyVPN-0.8.4-windows-portable`.

## Что не изменялось

- VPN/core логика не изменялась.
- Логика профилей и подписок не изменялась.
- Backup/export/import не изменялись.
- Portable data-папки не переименовывались.
- Массовая чистка upstream-остатков не выполнялась.

## Риск

Низкий.

Изменения затрагивают только версию приложения, appcast для автообновления и имя Windows portable-артефакта в GitHub Actions.
