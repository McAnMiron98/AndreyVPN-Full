import 'package:hooks_riverpod/hooks_riverpod.dart';

class StartupLaunch {
  const StartupLaunch({required this.isAutoStart});

  factory StartupLaunch.fromArguments(List<String> arguments) {
    return StartupLaunch(isAutoStart: arguments.contains('--autostart'));
  }

  final bool isAutoStart;
}

final startupLaunchProvider = Provider<StartupLaunch>(
  (ref) => const StartupLaunch(isAutoStart: false),
);
