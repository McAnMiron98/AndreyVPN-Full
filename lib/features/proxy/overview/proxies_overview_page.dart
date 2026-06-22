import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:andreyvpn/core/localization/translations.dart';
import 'package:andreyvpn/core/model/failures.dart';
import 'package:andreyvpn/core/notification/in_app_notification_controller.dart';
import 'package:andreyvpn/core/router/dialog/dialog_notifier.dart';
import 'package:andreyvpn/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:andreyvpn/features/proxy/widget/proxy_tile.dart';
import 'package:andreyvpn/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:andreyvpn/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxiesOverviewPage extends HookConsumerWidget with PresLogger {
  const ProxiesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final editing = useState(false);
    final selectedForRemoval = useState<Set<String>>(<String>{});

    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final sortBy = ref.watch(proxiesSortNotifierProvider);

    // final selectActiveProxyMutation = useMutation(
    //   initialOnFailure: (error) => CustomToast.error(t.presentShortError(error)).show(context),
    // );

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.proxies.title),
        actions: [
          if (!editing.value)
            TextButton.icon(
              onPressed: () {
                selectedForRemoval.value = <String>{};
                editing.value = true;
              },
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Редактировать'),
            )
          else ...[
            TextButton(
              onPressed: () {
                selectedForRemoval.value = <String>{};
                editing.value = false;
              },
              child: const Text('Отмена'),
            ),
            IconButton(
              tooltip: 'Удалить выбранные серверы',
              onPressed: selectedForRemoval.value.isEmpty
                  ? null
                  : () async {
                      final count = selectedForRemoval.value.length;
                      final confirmed = await ref.read(dialogNotifierProvider.notifier).showConfirmation(
                            title: 'Удалить серверы',
                            message:
                                'Выбранные серверы ($count) будут удалены из текущей подписки и не вернутся после её обновления.',
                            icon: Icons.delete_outline_rounded,
                            positiveBtnTxt: 'Удалить',
                          );
                      if (!confirmed) return;

                      try {
                        await ref
                            .read(proxiesOverviewNotifierProvider.notifier)
                            .deleteServers(selectedForRemoval.value);
                        selectedForRemoval.value = <String>{};
                        editing.value = false;
                        ref
                            .read(inAppNotificationControllerProvider)
                            .showSuccessToast('Серверы удалены: $count');
                      } catch (error) {
                        ref
                            .read(inAppNotificationControllerProvider)
                            .showErrorToast('Не удалось удалить серверы: $error');
                      }
                    },
              icon: Badge(
                isLabelVisible: selectedForRemoval.value.isNotEmpty,
                label: Text('${selectedForRemoval.value.length}'),
                child: const Icon(Icons.delete_outline_rounded),
              ),
            ),
          ],
          if (!editing.value)
            PopupMenuButton<ProxiesSort>(
              initialValue: sortBy,
              onSelected: ref.read(proxiesSortNotifierProvider.notifier).update,
              icon: const Icon(FluentIcons.arrow_sort_24_regular),
              tooltip: t.pages.proxies.sort,
              itemBuilder: (context) {
                return [...ProxiesSort.values.map((e) => PopupMenuItem(value: e, child: Text(e.present(t))))];
              },
            ),
          const Gap(8),
        ],
      ),
      floatingActionButton: editing.value
          ? null
          : FloatingActionButton(
              onPressed: () async => await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest("select"),
              tooltip: t.pages.proxies.testDelay,
              child: const Icon(FluentIcons.flash_24_filled),
            ),
      body: proxies.when(
        data: (group) => group != null
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final crossAxisCount = PlatformUtils.isMobile && width < 600 ? 1 : max(1, (width / 260).floor());
                  final removableServerCount = group.items.where(_canRemoveProxy).length;
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 86),
                    itemCount: group.items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisExtent: 64,
                    ),
                    itemBuilder: (context, index) {
                      final proxy = group.items[index];
                      final removalEnabled = _canRemoveProxy(proxy);
                      return ProxyTile(
                        proxy,
                        selected: group.selected == proxy.tag,
                        editing: editing.value,
                        removalEnabled: removalEnabled,
                        removalSelected: selectedForRemoval.value.contains(proxy.tag),
                        onTap: editing.value
                            ? removalEnabled
                                  ? () {
                                      final next = <String>{...selectedForRemoval.value};
                                      if (next.contains(proxy.tag)) {
                                        next.remove(proxy.tag);
                                      } else {
                                        if (next.length >= removableServerCount - 1) {
                                          ref
                                              .read(inAppNotificationControllerProvider)
                                              .showErrorToast('В подписке должен остаться хотя бы один сервер');
                                          return;
                                        }
                                        next.add(proxy.tag);
                                      }
                                      selectedForRemoval.value = next;
                                    }
                                  : null
                            : () async {
                                await ref
                                    .read(proxiesOverviewNotifierProvider.notifier)
                                    .changeProxy(group.tag, proxy.tag);
                              },
                      );
                    },
                  );
                },
              )
            : Center(child: Text(t.pages.proxies.empty)),
        error: (error, stackTrace) => Center(child: Text(t.presentShortError(error))),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  bool _canRemoveProxy(OutboundInfo proxy) {
    if (proxy.isGroup) return false;
    final tag = proxy.tag.trim().toLowerCase();
    final name = proxy.tagDisplay.trim().toLowerCase();
    return tag != 'lowest' && tag != 'balance' && name != 'lowest' && name != 'balance';
  }
}
