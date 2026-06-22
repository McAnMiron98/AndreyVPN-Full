import 'dart:async';

import 'package:flutter/material.dart';
import 'package:andreyvpn/core/preferences/actions_at_closing.dart';
import 'package:andreyvpn/core/preferences/general_preferences.dart';
import 'package:andreyvpn/core/router/dialog/dialog_notifier.dart';
import 'package:andreyvpn/core/router/go_router/go_router_notifier.dart';
import 'package:andreyvpn/features/window/notifier/window_notifier.dart';
import 'package:andreyvpn/utils/custom_loggers.dart';
import 'package:andreyvpn/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';

class WindowWrapper extends StatefulHookConsumerWidget {
  const WindowWrapper(this.child, {super.key});

  final Widget child;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _WindowWrapperState();
}

class _WindowWrapperState extends ConsumerState<WindowWrapper> with WindowListener, AppLogger {
  late AlertDialog closeDialog;

  bool isWindowClosingDialogOpened = false;
  Timer? _windowStateSaveTimer;

  @override
  Widget build(BuildContext context) {
    ref.watch(windowNotifierProvider);

    return widget.child;
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    if (PlatformUtils.isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await windowManager.setPreventClose(true);
      });
    }
  }

  @override
  void dispose() {
    _windowStateSaveTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  void _scheduleWindowStateSave() {
    _windowStateSaveTimer?.cancel();
    _windowStateSaveTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(windowNotifierProvider.notifier).saveWindowState();
    });
  }

  @override
  Future<void> onWindowClose() async {
    if (rootNavKey.currentContext == null) {
      await ref.read(windowNotifierProvider.notifier).hide();
      return;
    }

    switch (ref.read(Preferences.actionAtClose)) {
      case ActionsAtClosing.ask:
        if (isWindowClosingDialogOpened) return;
        isWindowClosingDialogOpened = true;
        await ref.read(dialogNotifierProvider.notifier).showWindowClosing();
        isWindowClosingDialogOpened = false;

      case ActionsAtClosing.hide:
        await ref.read(windowNotifierProvider.notifier).hide();

      case ActionsAtClosing.exit:
        await ref.read(windowNotifierProvider.notifier).exit();
    }
  }

  @override
  Future<void> onWindowResized() async {
    _scheduleWindowStateSave();
  }

  @override
  Future<void> onWindowMoved() async {
    _scheduleWindowStateSave();
  }

  @override
  Future<void> onWindowMaximize() async {
    _windowStateSaveTimer?.cancel();
    await ref.read(windowNotifierProvider.notifier).saveWindowState();
  }

  @override
  Future<void> onWindowUnmaximize() async {
    _windowStateSaveTimer?.cancel();
    await ref.read(windowNotifierProvider.notifier).saveWindowState();
  }

  @override
  void onWindowFocus() {
    setState(() {});
  }
}
