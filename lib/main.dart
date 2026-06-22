import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:andreyvpn/bootstrap.dart';
import 'package:andreyvpn/core/directories/directories_provider.dart';
import 'package:andreyvpn/core/logger/rotating_file_log.dart';
import 'package:andreyvpn/core/model/environment.dart';
import 'package:andreyvpn/features/settings/notifier/full_backup_notifier.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // final widgetsBinding = SentryWidgetsFlutterBinding.ensureInitialized();
  // debugPaintSizeEnabled = true;

  if (Platform.isWindows) {
    await RotatingFileLog.initializeDetailedFlag(
      File(p.join(AppDirectories.getPortableDirectory().path, 'shared_preferences.json')),
    );
  }
  await FullBackupNotifier.processPendingRestoreIfNeeded();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
  );

  return await lazyBootstrap(
    widgetsBinding,
    Environment.dev,
    startupArguments: arguments,
  );
}
