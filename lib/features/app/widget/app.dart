import 'package:accessibility_tools/accessibility_tools.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:andreyvpn/core/directories/directories_provider.dart';
import 'package:andreyvpn/core/localization/locale_extensions.dart';
import 'package:andreyvpn/core/localization/locale_preferences.dart';
import 'package:andreyvpn/core/localization/translations.dart';
import 'package:andreyvpn/core/model/constants.dart';
import 'package:andreyvpn/core/app_info/app_info_provider.dart';
import 'package:andreyvpn/core/router/dialog/dialog_notifier.dart';
import 'package:andreyvpn/features/app_update/notifier/app_update_notifier.dart';
import 'package:andreyvpn/features/app_update/notifier/app_update_state.dart';
import 'package:andreyvpn/core/notification/in_app_notification_controller.dart';
import 'package:andreyvpn/core/router/go_router/go_router_notifier.dart';
import 'package:andreyvpn/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:andreyvpn/core/theme/app_theme.dart';
import 'package:andreyvpn/core/theme/theme_preferences.dart';
import 'package:andreyvpn/features/connection/widget/connection_wrapper.dart';
import 'package:andreyvpn/features/per_app_proxy/overview/per_app_proxy_service_notifier.dart';
import 'package:andreyvpn/features/profile/notifier/profiles_update_notifier.dart';
import 'package:andreyvpn/features/shortcut/shortcut_wrapper.dart';
import 'package:andreyvpn/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:andreyvpn/features/window/widget/window_wrapper.dart';
import 'package:andreyvpn/andreyvpncore/andreyvpn_core_service_provider.dart';
import 'package:andreyvpn/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';

bool _debugAccessibility = false;
bool isOnPauseCalled = false;

class App extends HookConsumerWidget with WidgetsBindingObserver, PresLogger {
  const App({super.key});

  void onInactive(WidgetRef ref) {
    onPause(ref);
  }

  void onPause(WidgetRef ref) {
    if (PlatformUtils.isDesktop) return;
    isOnPauseCalled = true;
    ref.read(andreyvpnCoreServiceProvider).closeFront();
  }

  void onResume(WidgetRef ref) {
    // if (PlatformUtils.isDesktop) return;
    ref.read(andreyvpnCoreServiceProvider).init();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isOnPauseCalled && PlatformUtils.isAndroid) ref.invalidate(perAppProxyServiceProvider);
      isOnPauseCalled = false;
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    setupStateListener(ref);
    final router = ref.watch(goRouterNotiferProvider);
    final locale = ref.watch(localePreferencesProvider);
    final themeMode = ref.watch(themePreferencesProvider);
    final theme = AppTheme(themeMode, locale.preferredFontFamily);
    final activeBreakpoint = Breakpoint(context).activeBreakpoint;

    ref.listen(foregroundProfilesUpdateNotifierProvider, (_, _) {});
    if (PlatformUtils.isAndroid) ref.listen(perAppProxyServiceProvider, (_, _) {});
    if (PlatformUtils.isDesktop) ref.listen(systemTrayNotifierProvider, (_, _) {});

    useEffect(() {
      Future.microtask(() async {
        final appInfo = ref.read(appInfoProvider).requireValue;
        final updateState = await ref.read(appUpdateNotifierProvider.notifier).check();
        if (updateState is AppUpdateStateAvailable) {
          await ref.read(dialogNotifierProvider.notifier).showNewVersion(
            currentVersion: appInfo.version,
            newVersion: updateState.versionInfo,
            canIgnore: true,
          );
        }
      });
      return null;
    }, const []);

    // updating ActiveBreakpointNotifier value
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeBreakpointNotifierProvider.notifier).update(activeBreakpoint);
      });
      return null;
    }, [activeBreakpoint]);
    return WindowWrapper(
      ShortcutWrapper(
        ToastificationWrapper(
          child: ConnectionWrapper(
            DynamicColorBuilder(
              builder: (ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
                return MaterialApp.router(
                  routerConfig: router,
                  locale: locale.flutterLocale,
                  supportedLocales: AppLocaleUtils.supportedLocales,
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  debugShowCheckedModeBanner: false,
                  themeMode: themeMode.flutterThemeMode,
                  theme: theme.lightTheme(lightColorScheme),
                  darkTheme: theme.darkTheme(darkColorScheme),
                  title: Constants.appName,
                  builder: (context, child) {
                    final theme = Theme.of(context);
                    child = child ?? const SizedBox();
                    if (kDebugMode && _debugAccessibility) {
                      return AccessibilityTools(checkFontOverflows: true, child: child);
                    }
                    return AnnotatedRegion<SystemUiOverlayStyle>(
                      value: SystemUiOverlayStyle(
                        statusBarColor: theme.scaffoldBackgroundColor,
                        systemNavigationBarColor: theme.scaffoldBackgroundColor,
                        systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
                            ? Brightness.light
                            : Brightness.dark,
                      ),
                      child: child,
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // @override
  // Widget build1(BuildContext context, WidgetRef ref) {
  //   setupStateListener(ref);
  //   // setupQuickSettings(ref);
  //   final router = ref.watch(routerProvider);
  //   final locale = ref.watch(localePreferencesProvider);
  //   final themeMode = ref.watch(themePreferencesProvider);
  //   final theme = AppTheme(themeMode, locale.preferredFontFamily);
  //   final upgrader = ref.watch(upgraderProvider);

  //   ref.listen(foregroundProfilesUpdateNotifierProvider, (_, __) {});

  //   return WindowWrapper(
  //     TrayWrapper(
  //       ShortcutWrapper(
  //         ConnectionWrapper(
  //           PlatformProvider(
  //               settings: PlatformSettingsData(
  //                 iosUsesMaterialWidgets: true,
  //               ),
  //               builder: (context) => DynamicColorBuilder(
  //                     builder: (ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
  //                       return PlatformApp.router(
  //                         routerConfig: router,
  //                         locale: locale.flutterLocale,
  //                         supportedLocales: AppLocaleUtils.supportedLocales,
  //                         localizationsDelegates: GlobalMaterialLocalizations.delegates,
  //                         debugShowCheckedModeBanner: false,
  //                         material: (context, platform) => MaterialAppRouterData(
  //                           theme: theme.lightTheme(lightColorScheme),
  //                           darkTheme: theme.darkTheme(darkColorScheme),
  //                           themeMode: themeMode.flutterThemeMode,
  //                         ),
  //                         cupertino: (context, platform) {
  //                           final sysDark = MediaQuery.of(context).platformBrightness == Brightness.dark;

  //                           return CupertinoAppRouterData(theme: theme.cupertinoThemeData(sysDark, lightColorScheme, darkColorScheme));
  //                         },
  //                         title: Constants.appName,
  //                         builder: (context, child) {
  //                           child = UpgradeAlert(
  //                             upgrader: upgrader,
  //                             navigatorKey: router.routerDelegate.navigatorKey,
  //                             child: child ?? const SizedBox(),
  //                           );
  //                           if (kDebugMode && _debugAccessibility) {
  //                             return AccessibilityTools(
  //                               checkFontOverflows: true,
  //                               child: child,
  //                             );
  //                           }
  //                           return child;
  //                         },
  //                       );
  //                     },
  //                   )),
  //         ),
  //       ),
  //     ),
  //   );
  // }

  void setupStateListener(WidgetRef ref) {
    final appLifecycleState = useAppLifecycleState();

    useEffect(() {
      loggy.info("current app state");
      loggy.info(appLifecycleState);
      if (appLifecycleState == AppLifecycleState.paused) {
        onPause(ref);
      } else if (appLifecycleState == AppLifecycleState.inactive) {
        onInactive(ref);
      } else if (appLifecycleState == AppLifecycleState.resumed) {
        onResume(ref);
      }
      return null;
    }, [appLifecycleState]);
  }
}
