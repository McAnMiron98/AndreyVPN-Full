# AndreyVPN

Кастомный Windows VPN-клиент на базе open-source проекта Hiddify.

## Текущая версия

AndreyVPN 0.8.0

## Сборка

Windows-сборка выполняется через GitHub Actions, workflow `Build Windows AndreyVPN`.

## Обновления

Portable-версии распространяются через GitHub Releases. Приложение умеет проверять обновления и обновляться через отдельный `AndreyVPNUpdater.exe`.

## Важно

Часть внутренних package/import/core-названий может всё ещё содержать `hiddify`. Это технические имена upstream-проекта и VPN-core интеграции. Они оставлены намеренно, чтобы не сломать сборку.
