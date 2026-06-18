# AndreyVPN 1.0.6 — System Proxy Recovery & Startup Fix

## Что изменено

- Добавлена автоматическая очистка зависшего системного прокси при старте Windows-приложения.
- При запуске AndreyVPN проверяет системный proxy Windows.
- Если proxy включён и указывает на локальный mixed proxy AndreyVPN (`127.0.0.1:<mixed-port>` или `localhost:<mixed-port>`), приложение отключает `ProxyEnable`.
- Добавлено уведомление Windows/WinINet о смене proxy-настроек после очистки.
- Добавлен диагностический лог `andreyvpn_data/logs/andreyvpn_system_proxy_recovery.log`.
- Автозагрузка на Windows переведена с обычной startup/Run-записи на задачу Windows Task Scheduler.
- Новая задача автозагрузки создаётся с `Run with highest privileges`, чтобы AndreyVPN мог стартовать после входа в Windows даже при elevated/admin-сценарии.
- При включении автозагрузки старый legacy startup-entry удаляется, чтобы не было дублей.
- При обнаружении старой legacy автозагрузки приложение пытается автоматически мигрировать её на scheduled task.
- Добавлен диагностический лог `andreyvpn_data/logs/andreyvpn_autostart.log`.

## Что не менялось

- VPN core logic не менялась.
- Логика подключения/отключения VPN не менялась.
- Логика выбора серверов и tray server switch не менялась.
- Подписки, backup/import, portable storage и JSON fallback не менялись.
