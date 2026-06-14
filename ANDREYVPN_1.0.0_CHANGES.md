# AndreyVPN 1.0.0 — Full Dart Package Rebranding

## Изменения

- Обновлена версия приложения до `1.0.0+67`.
- Переименовано внутреннее Dart package name:
  - `hiddify` → `andreyvpn`.
- Обновлены Dart imports по проекту:
  - `package:hiddify/...` → `package:andreyvpn/...`.
- Обновлён Windows CMake project name:
  - `hiddify` → `andreyvpn`.
- Обновлён Windows auto-start package name:
  - `Hiddify.HiddifyNext` → `AndreyVPN`.
- Обновлены версии в `appcast.xml` и GitHub Actions packaging.
- Логическая VPN/core часть не изменялась.

## Что намеренно не трогалось

- `lib/hiddifycore/`.
- `hiddify-core/` submodule.
- Generated protobuf/bindings.
- Core API names/classes, которые связаны с upstream core.
- `LICENSE.md` и юридические упоминания upstream.

## Риск

Высокий: переименование Dart package name затрагивает большое количество файлов и может повлиять на сборку.
