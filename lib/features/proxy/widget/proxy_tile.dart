import 'package:flutter/material.dart';
import 'package:andreyvpn/core/router/dialog/dialog_notifier.dart';
import 'package:andreyvpn/features/proxy/active/ip_widget.dart';
import 'package:andreyvpn/gen/fonts.gen.dart';
import 'package:andreyvpn/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:andreyvpn/utils/custom_loggers.dart';
import 'package:andreyvpn/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxyTile extends HookConsumerWidget with PresLogger {
  const ProxyTile(this.proxy, {super.key, required this.selected, required this.onTap});

  final OutboundInfo proxy;
  final bool selected;
  final GestureTapCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final countryTitle = _countryTitle(proxy);
    final cleanName = _cleanServerName(proxy.tagDisplay);
    final details = _detailsLine(proxy, selected);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      color: selected ? theme.colorScheme.primaryContainer : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () async => await ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: proxy),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IPCountryFlag(
                countryCode: proxy.ipinfo.countryCode,
                organization: proxy.ipinfo.org,
                size: 42,
                padding: const EdgeInsetsDirectional.only(end: 10, top: 2),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      countryTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFamily: PlatformUtils.isWindows ? FontFamily.emoji : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      cleanName.isEmpty ? proxy.tagDisplay : cleanName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: PlatformUtils.isWindows ? FontFamily.emoji : null,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _detailsLine(OutboundInfo proxy, bool selected) {
    final parts = <String>[];

    if (selected) {
      parts.add('✓ Подключен');
    }

    final type = proxy.type.trim();
    if (type.isNotEmpty) {
      parts.add(type.toUpperCase());
    }

    final transport = _transportHint(proxy);
    if (transport.isNotEmpty && transport.toUpperCase() != type.toUpperCase()) {
      parts.add(transport);
    }

    if (proxy.isSecure && !parts.any((part) => part.toLowerCase().contains('tls') || part.toLowerCase().contains('reality'))) {
      parts.add('Secure');
    }

    if (proxy.urlTestDelay != 0) {
      parts.add(proxy.urlTestDelay > 65000 ? 'ping ×' : '${proxy.urlTestDelay} ms');
    }

    if (proxy.isGroup) {
      final selectedTag = _cleanServerName(proxy.groupSelectedTagDisplay.trim());
      if (selectedTag.isNotEmpty) {
        parts.add('Balancer: $selectedTag');
      }
    }

    return parts.join(' • ');
  }

  String _countryTitle(OutboundInfo proxy) {
    final code = proxy.ipinfo.countryCode.trim().toUpperCase();
    final countryName = _countryNames[code];

    if (countryName != null) {
      return countryName;
    }

    final fromName = _countryFromName(proxy.tagDisplay);
    if (fromName != null) {
      return fromName;
    }

    return 'Unknown country';
  }

  String _cleanServerName(String value) {
    var result = value.trim();

    // Remove one or more leading flag emojis from subscription names.
    result = result.replaceFirst(RegExp(r'^(?:[\u{1F1E6}-\u{1F1FF}]{2}\s*)+', unicode: true), '');

    // Remove common technical prefixes left by some subscription providers.
    result = result.replaceFirst(RegExp(r'^\s*[-–—|•]+\s*'), '');

    return result.trim();
  }

  String? _countryFromName(String value) {
    final normalized = value.toLowerCase();
    for (final entry in _countryNameKeywords.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  String _transportHint(OutboundInfo proxy) {
    final text = '${proxy.tagDisplay} ${proxy.groupSelectedTagDisplay} ${proxy.host}'.toLowerCase();

    if (text.contains('reality')) return 'Reality';
    if (text.contains('xhttp')) return 'XHTTP';
    if (text.contains('grpc')) return 'gRPC';
    if (text.contains('ws') || text.contains('websocket')) return 'WS';
    if (text.contains('tls')) return 'TLS';

    return '';
  }
}

const Map<String, String> _countryNames = {
  'AT': 'Austria',
  'AU': 'Australia',
  'AZ': 'Azerbaijan',
  'BE': 'Belgium',
  'BR': 'Brazil',
  'CA': 'Canada',
  'CH': 'Switzerland',
  'CN': 'China',
  'CZ': 'Czechia',
  'DE': 'Germany',
  'DK': 'Denmark',
  'EE': 'Estonia',
  'ES': 'Spain',
  'FI': 'Finland',
  'FR': 'France',
  'GB': 'United Kingdom',
  'HK': 'Hong Kong',
  'IL': 'Israel',
  'IN': 'India',
  'IR': 'Iran',
  'IT': 'Italy',
  'JP': 'Japan',
  'KZ': 'Kazakhstan',
  'LV': 'Latvia',
  'NL': 'Netherlands',
  'NO': 'Norway',
  'PL': 'Poland',
  'RU': 'Russia',
  'SE': 'Sweden',
  'SG': 'Singapore',
  'TR': 'Turkey',
  'UA': 'Ukraine',
  'US': 'United States',
};

const Map<String, String> _countryNameKeywords = {
  'austria': 'Austria',
  'australia': 'Australia',
  'azerbaijan': 'Azerbaijan',
  'belgium': 'Belgium',
  'brazil': 'Brazil',
  'canada': 'Canada',
  'czech': 'Czechia',
  'germany': 'Germany',
  'denmark': 'Denmark',
  'estonia': 'Estonia',
  'spain': 'Spain',
  'finland': 'Finland',
  'france': 'France',
  'united kingdom': 'United Kingdom',
  'uk': 'United Kingdom',
  'israel': 'Israel',
  'india': 'India',
  'iran': 'Iran',
  'italy': 'Italy',
  'japan': 'Japan',
  'kazakhstan': 'Kazakhstan',
  'latvia': 'Latvia',
  'netherlands': 'Netherlands',
  'norway': 'Norway',
  'poland': 'Poland',
  'russia': 'Russia',
  'россия': 'Russia',
  'sweden': 'Sweden',
  'singapore': 'Singapore',
  'turkey': 'Turkey',
  'ukraine': 'Ukraine',
  'united states': 'United States',
  'usa': 'United States',
  'new york': 'United States',
};
