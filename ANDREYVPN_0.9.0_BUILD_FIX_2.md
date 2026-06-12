# AndreyVPN 0.9.0 Build Fix 2

Исправление ошибки GitHub Actions `build-windows-portable` после удаления Hiddify.

## Что исправлено

- В `Makefile` добавлен этап `clean-stale-hiddify` перед `flutter pub get`, `build_runner` и `slang`.
- Этот этап удаляет старые папки `lib/hiddifycore`, `test/hiddifycore`, Android `com/hiddify` и возможные старые generated-файлы из `.dart_tool`.
- Это защищает сборку GitHub Actions от ситуации, когда старые файлы остались в репозитории после переименования/замены архива.
- В workflow `build-windows-andrey.yml` имя portable-архива обновлено с `0.8.0` на `0.9.0`.

## Почему это было нужно

Лог сборки показывал, что зависимость `circle_flags` уже исправлена и скачивается с pub.dev, но `build_runner` всё ещё видел старый файл:

`lib/hiddifycore/hiddify_core_service_provider.dart`

Значит в GitHub-репозитории оставались старые файлы, которых уже не было в очищенном архиве. Теперь перед генерацией они принудительно удаляются.
