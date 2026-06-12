import 'package:andreyvpn/core/directories/directories_provider.dart';
import 'package:andreyvpn/core/notification/in_app_notification_controller.dart';
import 'package:andreyvpn/core/preferences/general_preferences.dart';
import 'package:andreyvpn/andreyvpncore/andreyvpn_core_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'andreyvpn_core_service_provider.g.dart';

@Riverpod(keepAlive: true, dependencies: [AppDirectories, DebugModeNotifier, inAppNotificationController])
AndreyVPNCoreService andreyvpnCoreService(Ref ref) {
  return AndreyVPNCoreService(ref);
}
