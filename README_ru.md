# AndreyVPN

AndreyVPN — portable VPN-клиент для Windows.

## Текущая версия

AndreyVPN 0.9.1

## Portable-хранилище

Пользовательские данные хранятся рядом с `AndreyVPN.exe` в папке:

```text
andreyvpn_data/
```

В этой папке находятся профили, настройки, логи, состояние бэкапа и runtime-данные.

## Сборка

Windows-сборка выполняется через GitHub Actions, workflow `Build Windows AndreyVPN`.

## Обновления

Portable-версии распространяются через GitHub Releases. Обновление выполняется через `AndreyVPNUpdater.exe`.

## Важно

Некоторые внутренние имена исходного кода намеренно оставлены без изменений там, где они относятся к upstream core integration и не видны пользователю.
