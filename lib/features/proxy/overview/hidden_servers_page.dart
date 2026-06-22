import 'package:flutter/material.dart';
import 'package:andreyvpn/core/notification/in_app_notification_controller.dart';
import 'package:andreyvpn/features/connection/notifier/connection_notifier.dart';
import 'package:andreyvpn/features/profile/data/profile_data_providers.dart';
import 'package:andreyvpn/features/profile/data/profile_server_exclusion_store.dart';
import 'package:andreyvpn/features/profile/model/profile_entity.dart';
import 'package:andreyvpn/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HiddenServersPage extends ConsumerStatefulWidget {
  const HiddenServersPage({super.key});

  @override
  ConsumerState<HiddenServersPage> createState() => _HiddenServersPageState();
}

class _HiddenServersPageState extends ConsumerState<HiddenServersPage> {
  List<HiddenServer> _servers = const [];
  bool _loading = true;
  Set<String> _restoring = const {};
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final profile = await ref.read(activeProfileProvider.future);
      final repository = await ref.read(profileRepositoryProvider.future);
      final servers = profile == null ? const <HiddenServer>[] : repository.getHiddenServers(profile.id);
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _restore(Set<String> tags) async {
    if (tags.isEmpty || _restoring.isNotEmpty) return;
    final profile = await ref.read(activeProfileProvider.future);
    if (profile is! RemoteProfileEntity) {
      ref
          .read(inAppNotificationControllerProvider)
          .showErrorToast('Автоматическое восстановление доступно только для подписок');
      return;
    }

    setState(() => _restoring = tags);
    try {
      final repository = await ref.read(profileRepositoryProvider.future);
      await repository.restoreServers(profile, tags).match(
        (error) => throw error,
        (_) async {
          await ref.read(connectionNotifierProvider.notifier).reconnect(profile);
        },
      ).run();
      ref
          .read(inAppNotificationControllerProvider)
          .showSuccessToast(tags.length == 1 ? 'Сервер восстановлен' : 'Серверы восстановлены: ${tags.length}');
      await _load();
    } catch (error) {
      ref
          .read(inAppNotificationControllerProvider)
          .showErrorToast('Не удалось восстановить серверы: $error');
    } finally {
      if (mounted) setState(() => _restoring = const {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Скрытые серверы'),
        actions: [
          if (_servers.isNotEmpty)
            TextButton.icon(
              onPressed: _restoring.isEmpty
                  ? () => _restore(_servers.map((server) => server.tag).toSet())
                  : null,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Вернуть все'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: switch ((_loading, _error, _servers.isEmpty)) {
        (true, _, _) => const Center(child: CircularProgressIndicator()),
        (false, final error?, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Не удалось загрузить скрытые серверы:\n$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
        (false, null, true) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_outlined, size: 44),
              SizedBox(height: 12),
              Text('Скрытых серверов нет'),
            ],
          ),
        ),
        _ => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: _servers.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final server = _servers[index];
            final restoring = _restoring.contains(server.tag);
            return ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(server.name),
              subtitle: server.name == server.tag ? null : Text(server.tag),
              trailing: restoring
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Вернуть сервер',
                      onPressed: _restoring.isEmpty ? () => _restore({server.tag}) : null,
                      icon: const Icon(Icons.restore_rounded),
                    ),
            );
          },
        ),
      },
    );
  }
}
