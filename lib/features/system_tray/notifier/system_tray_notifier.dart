import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:andreyvpn/core/localization/translations.dart';
import 'package:andreyvpn/core/model/constants.dart';
import 'package:andreyvpn/core/win32_tray_focus_fix.dart';
import 'package:andreyvpn/features/connection/model/connection_status.dart';
import 'package:andreyvpn/features/connection/notifier/connection_notifier.dart';
import 'package:andreyvpn/features/proxy/active/active_proxy_notifier.dart';
import 'package:andreyvpn/features/proxy/data/proxy_data_providers.dart';
import 'package:andreyvpn/features/settings/data/config_option_repository.dart';
import 'package:andreyvpn/features/window/notifier/window_notifier.dart';
import 'package:andreyvpn/gen/assets.gen.dart';
import 'package:andreyvpn/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:andreyvpn/singbox/model/singbox_config_enum.dart';
import 'package:andreyvpn/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

part 'system_tray_notifier.g.dart';

@Riverpod(keepAlive: true)
class SystemTrayNotifier extends _$SystemTrayNotifier with TrayListener, AppLogger {
  bool listenerAdded = false;
  bool _trayMenuOpening = false;
  DateTime? _lastTrayRightMouseDownAt;
  @override
  Future<void> build() async {
    assert(PlatformUtils.isDesktop);
    if (!listenerAdded) {
      trayManager.addListener(this);
      listenerAdded = true;
    }
    await _initializeTray();
  }

  Future<void> _initializeTray() async {
    final t = await ref.watch(translationsProvider.future);
    final urlTestDelay = await ref
        .watch(activeProxyNotifierProvider.future)
        .catchError((e) {
          loggy.warning("error getting active proxy", e);
          return OutboundInfo(urlTestDelay: 0);
        })
        .then((connection) => connection.urlTestDelay);
    final connection = await ref
        .watch(connectionNotifierProvider.future)
        .catchError((e) {
          loggy.warning("error getting connection status", e);
          return const ConnectionStatus.disconnected();
        })
        .then((connection) => _modifyConnectionStatus(connection, urlTestDelay));
    final serviceMode = ref.watch(ConfigOptions.serviceMode);

    await trayManager.setIcon(_trayIconPath(connection), isTemplate: PlatformUtils.isMacOS);
    if (!PlatformUtils.isLinux) await trayManager.setToolTip(_trayTooltip(connection, urlTestDelay, t));
    await trayManager.setContextMenu(await _trayMenu(connection, serviceMode, t));
  }

  Future<Menu> _trayMenu(ConnectionStatus connection, ServiceMode serviceMode, Translations t) async => Menu(
    items: [
      if (PlatformUtils.isLinux) ...[MenuItem(key: 'dashboard', label: t.common.dashboard), MenuItem.separator()],
      MenuItem(
        key: 'connection',
        label: switch (connection) {
          Disconnected() => t.connection.connect,
          Connecting() => t.connection.connecting,
          Connected() => t.connection.disconnect,
          Disconnecting() => t.connection.disconnecting,
        },
        disabled: connection.isSwitching,
      ),
      if (connection is Connected) ...[
        await _serverSwitchMenuItem(),
      ],
      MenuItem.submenu(
        label: t.pages.settings.inbound.serviceMode,
        icon: Assets.images.trayIconIco,
        submenu: Menu(
          items: [
            ...ServiceMode.values.map(
              (e) => MenuItem.checkbox(checked: e == serviceMode, key: e.name, label: e.present(t)),
            ),
          ],
        ),
      ),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: t.common.quit),
    ],
  );

  Future<MenuItem> _serverSwitchMenuItem() async {
    final items = <MenuItem>[];
    try {
      final groupEither = await ref.read(proxyRepositoryProvider).watchProxies().first.timeout(const Duration(seconds: 2));
      final group = groupEither.getOrElse((err) {
        loggy.warning('error loading tray proxy list', err);
        return null;
      });

      if (group != null) {
        final proxies = group.items.where(_isTraySwitchableProxy).toList()
          ..sort((a, b) {
            final ai = _pingSortValue(a.urlTestDelay);
            final bi = _pingSortValue(b.urlTestDelay);
            final delayCompare = ai.compareTo(bi);
            if (delayCompare != 0) return delayCompare;
            return _trayProxyName(a).compareTo(_trayProxyName(b));
          });

        for (final proxy in proxies) {
          items.add(
            MenuItem.checkbox(
              checked: group.selected == proxy.tag,
              key: _trayProxyKey(group.tag, proxy.tag),
              label: '${_trayProxyName(proxy)} — ${_trayPingLabel(proxy.urlTestDelay)}',
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      loggy.warning('error building tray server switch menu', error, stackTrace);
    }

    if (items.isEmpty) {
      items.add(MenuItem(key: 'tray_proxy_empty', label: 'Нет доступных серверов', disabled: true));
    }

    return MenuItem.submenu(
      key: 'tray_proxy_menu',
      label: 'Сменить сервер',
      submenu: Menu(items: items),
    );
  }

  bool _isTraySwitchableProxy(OutboundInfo proxy) {
    if (proxy.isGroup) return false;
    final tag = proxy.tag.trim().toLowerCase();
    final name = proxy.tagDisplay.trim().toLowerCase();
    return tag != 'lowest' && tag != 'balance' && name != 'lowest' && name != 'balance';
  }

  int _pingSortValue(int delay) {
    if (delay <= 0 || delay > 65000) return 1 << 30;
    return delay;
  }

  String _trayProxyName(OutboundInfo proxy) {
    final rawName = proxy.tagDisplay.trim().isNotEmpty ? proxy.tagDisplay.trim() : proxy.tag.trim();
    final name = rawName
        .replaceFirst(RegExp(r'^(?:[\u{1F1E6}-\u{1F1FF}]{2}\s*)+', unicode: true), '')
        .replaceFirst(RegExp(r'^\s*[-–—|•]+\s*'), '')
        .trim();
    return name.isEmpty ? rawName : name;
  }

  String _trayPingLabel(int delay) {
    if (delay <= 0 || delay > 65000) return 'ping —';
    return '$delay ms';
  }

  String _trayProxyKey(String groupTag, String proxyTag) {
    String encodePart(String value) => base64Url.encode(utf8.encode(value));
    return 'tray_proxy:${encodePart(groupTag)}:${encodePart(proxyTag)}';
  }

  (String groupTag, String proxyTag)? _decodeTrayProxyKey(String key) {
    final parts = key.split(':');
    if (parts.length != 3 || parts.first != 'tray_proxy') return null;
    try {
      String decodePart(String value) => utf8.decode(base64Url.decode(value));
      return (decodePart(parts[1]), decodePart(parts[2]));
    } catch (error, stackTrace) {
      loggy.warning('error decoding tray proxy key: [$key]', error, stackTrace);
      return null;
    }
  }

  String _trayIconPath(ConnectionStatus status) {
    final isDarkMode = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    const images = Assets.images;
    final isWindows = PlatformUtils.isWindows;
    switch (status) {
      case Connected():
        return isWindows ? images.trayIconConnectedIco : images.trayIconConnectedPng.path;
      case Connecting():
      case Disconnecting():
        return isWindows ? images.trayIconDisconnectedIco : images.trayIconDisconnectedPng.path;
      case Disconnected():
        return isWindows
            ? isDarkMode
                  ? images.trayIconIco
                  : images.trayIconDarkIco
            : isDarkMode
            ? images.trayIconDarkPng.path
            : images.trayIconPng.path;
    }
  }

  String _trayTooltip(ConnectionStatus connection, int urlTestDelay, Translations t) {
    final r = "${Constants.appName} - ${connection.present(t)}";
    if (connection is Connected) {
      if (Platform.isMacOS) windowManager.setBadgeLabel("${urlTestDelay}ms");
      return '$r : ${urlTestDelay}ms"';
    } else {
      if (Platform.isMacOS) windowManager.setBadgeLabel("-ms");
      return r;
    }
  }

  ConnectionStatus _modifyConnectionStatus(ConnectionStatus connection, int urlTestDelay) {
    if (connection is Connected) {
      return urlTestDelay > 0 && urlTestDelay < 65000 ? const Connected() : const Connecting();
    } else {
      return connection;
    }
  }

  @override
  Future<void> onTrayMenuItemClick(MenuItem menuItem) async {
    // if (menuItem.key == 'dashboard') {
    //   await ref.read(windowNotifierProvider.notifier).open();
    // }
    if (menuItem.key == 'dashboard') {
      await ref.read(windowNotifierProvider.notifier).show();
    } else if (menuItem.key == 'connection') {
      await ref.read(connectionNotifierProvider.notifier).toggleConnection();
    } else if (menuItem.key == 'quit') {
      await ref.read(windowNotifierProvider.notifier).exit();
    } else if (menuItem.key?.startsWith('tray_proxy:') ?? false) {
      final decoded = _decodeTrayProxyKey(menuItem.key!);
      if (decoded == null) return;
      final (groupTag, proxyTag) = decoded;
      loggy.debug('switching tray proxy, group: [$groupTag] - outbound: [$proxyTag]');
      await ref.read(proxyRepositoryProvider).selectProxy(groupTag, proxyTag).getOrElse((err) {
        loggy.warning('error selecting tray proxy', err);
        throw err;
      }).run();
      ref.invalidate(activeProxyNotifierProvider);
      await _initializeTray();
    } else if (menuItem.key != null && ServiceMode.values.any((mode) => mode.name == menuItem.key)) {
      final newMode = ServiceMode.values.byName(menuItem.key!);
      loggy.debug("switching service mode: [$newMode]");
      await ref.read(ConfigOptions.serviceMode.notifier).update(newMode);
    }
  }

  @override
  Future<void> onTrayIconMouseDown() async {
    // if (Platform.isMacOS) {
    //   await trayManager.popUpContextMenu();
    // } else {
    //   await ref.read(windowNotifierProvider.notifier).hideOrShow();
    // }
    await ref.read(windowNotifierProvider.notifier).showOrHide();
  }

  @override
  Future<void> onTrayIconRightMouseDown() async {
    final now = DateTime.now();
    final previousRightClickAt = _lastTrayRightMouseDownAt;
    _lastTrayRightMouseDownAt = now;

    if (_trayMenuOpening) {
      loggy.debug('tray right click ignored: popup already opening');
      return;
    }

    if (previousRightClickAt != null && now.difference(previousRightClickAt) < const Duration(milliseconds: 250)) {
      loggy.debug('tray right click ignored: duplicate event deltaMs=${now.difference(previousRightClickAt).inMilliseconds}');
      return;
    }

    _trayMenuOpening = true;
    final foregroundFix = Win32TrayFocusFix.prepareForNativeTrayMenu(expectedTitle: Constants.appName);
    loggy.debug('tray native popup start foregroundFix=[$foregroundFix]');
    try {
      await trayManager.popUpContextMenu();
      final pumpNudge = Win32TrayFocusFix.postMenuMessagePumpNudge();
      loggy.debug('tray native popup returned pumpNudge=[$pumpNudge]');
    } catch (error, stackTrace) {
      loggy.warning('tray native popup failed', error, stackTrace);
    } finally {
      _trayMenuOpening = false;
    }
  }
}

// @Riverpod(keepAlive: true)
// class SystemTrayNotifier extends _$SystemTrayNotifier with AppLogger {
//   @override
//   Future<void> build() async {
//     if (!PlatformUtils.isDesktop) return;

//     final activeProxy = await ref.watch(activeProxyNotifierProvider.future);
//     final delay = activeProxy.urlTestDelay;
//     final newConnectionStatus = delay > 0 && delay < 65000;
//     ConnectionStatus connection;
//     try {
//       connection = await ref.watch(connectionNotifierProvider.future);
//     } catch (e) {
//       loggy.warning("error getting connection status", e);
//       connection = const ConnectionStatus.disconnected();
//     }

//     final t = await ref.watch(translationsProvider.future);

//     var tooltip = Constants.appName;
//     final serviceMode = ref.watch(ConfigOptions.serviceMode);
//     if (connection is Disconnected) {
//       setIcon(connection);
//     } else if (newConnectionStatus) {
//       setIcon(const Connected());
//       tooltip = "$tooltip - ${connection.present(t)}";
//       if (newConnectionStatus) {
//         tooltip = "$tooltip : ${delay}ms";
//       } else {
//         tooltip = "$tooltip : -";
//       }
//       // else if (delay>1000)
//       //   SystemTrayNotifier.setIcon(timeout ? Disconnecting() : Connecting());
//     } else {
//       setIcon(const Disconnecting());
//       tooltip = "$tooltip - ${connection.present(t)}";
//     }
//     if (Platform.isMacOS) {
//       windowManager.setBadgeLabel("${delay}ms");
//     }
//     if (!Platform.isLinux) await trayManager.setToolTip(tooltip);

//     // final destinations = <(String label, String location)>[
//     //   (t.home.pageTitle, const HomeRoute().location),
//     //   (t.proxies.pageTitle, const ProfilesOverviewRoute().location),
//     //   (t.logs.title, const LogsOverviewRoute().location),
//     //   // (t.settings.pageTitle, const SettingsRoute().location),
//     //   (t.about.pageTitle, const AboutRoute().location),
//     // ];

//     // loggy.debug('updating system tray');

//     final menu = Menu(
//       items: [
//         MenuItem(
//           label: t.tray.dashboard,
//           onClick: (_) async {
//             await ref.read(windowNotifierProvider.notifier).open();
//           },
//         ),
//         MenuItem.separator(),
//         MenuItem.checkbox(
//           label: switch (connection) {
//             Disconnected() => t.tray.status.connect,
//             Connecting() => t.tray.status.connecting,
//             Connected() => t.tray.status.disconnect,
//             Disconnecting() => t.tray.status.disconnecting,
//           },
//           // checked: connection.isConnected,
//           checked: false,
//           disabled: connection.isSwitching,
//           onClick: (_) async {
//            await ref.read(connectionNotifierProvider.notifier).toggleConnection();
//          },
//        ),
//         MenuItem.separator(),
//         MenuItem(
//           label: t.config.serviceMode,
//           icon: Assets.images.trayIconIco,
//           disabled: true,
//         ),

//         ...ServiceMode.values.map(
//           (e) => MenuItem.checkbox(
//             checked: e == serviceMode,
//             key: e.name,
//             label: e.present(t),
//             onClick: (menuItem) async {
//               final newMode = ServiceMode.values.byName(menuItem.key!);
//               loggy.debug("switching service mode: [$newMode]");
//               await ref.read(ConfigOptions.serviceMode.notifier).update(newMode);
//             },
//           ),
//         ),

//         // MenuItem.submenu(
//         //   label: t.tray.open,
//         //   submenu: Menu(
//         //     items: [
//         //       ...destinations.map(
//         //         (e) => MenuItem(
//         //           label: e.$1,
//         //           onClick: (_) async {
//         //             await ref.read(windowNotifierProvider.notifier).open();
//         //             ref.read(routerProvider).go(e.$2);
//         //           },
//         //         ),
//         //       ),
//         //     ],
//         //   ),
//         // ),
//         MenuItem.separator(),
//         MenuItem(
//           label: t.tray.quit,
//           onClick: (_) async {
//             return ref.read(windowNotifierProvider.notifier).quit();
//           },
//         ),
//       ],
//     );

//     await trayManager.setContextMenu(menu);
//   }

//   static void setIcon(ConnectionStatus status) {
//     if (!PlatformUtils.isDesktop) return;
//     trayManager
//         .setIcon(
//           _trayIconPath(status),
//           isTemplate: Platform.isMacOS,
//         )
//         .asStream();
//   }

//   static String _trayIconPath(ConnectionStatus status) {
//     if (Platform.isWindows) {
//       final Brightness brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
//       final isDarkMode = brightness == Brightness.dark;
//       switch (status) {
//         case Connected():
//           return Assets.images.trayIconConnectedIco;
//         case Connecting():
//           return Assets.images.trayIconDisconnectedIco;
//         case Disconnecting():
//           return Assets.images.trayIconDisconnectedIco;
//         case Disconnected():
//           if (isDarkMode) {
//             return Assets.images.trayIconIco;
//           } else {
//             return Assets.images.trayIconDarkIco;
//           }
//       }
//     }
//     // const isDarkMode = false;
//     switch (status) {
//       case Connected():
//         return Assets.images.trayIconConnectedPng.path;
//       case Connecting():
//         return Assets.images.trayIconDisconnectedPng.path;
//       case Disconnecting():
//         return Assets.images.trayIconDisconnectedPng.path;
//       case Disconnected():
//         // if (isDarkMode) {
//         //   return Assets.images.trayIconDarkPng.path;
//         // } else {
//         //   return Assets.images.trayIconPng.path;
//         // }
//         return Assets.images.trayIconPng.path;
//     }
//     // return Assets.images.trayIconPng.path;
//   }
// }
