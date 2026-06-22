import 'package:flutter/material.dart';
import 'package:andreyvpn/core/router/dialog/dialog_notifier.dart';
import 'package:andreyvpn/features/proxy/active/ip_widget.dart';
import 'package:andreyvpn/gen/fonts.gen.dart';
import 'package:andreyvpn/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:andreyvpn/utils/custom_loggers.dart';
import 'package:andreyvpn/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxyTile extends HookConsumerWidget with PresLogger {
  const ProxyTile(
    this.proxy, {
    super.key,
    required this.selected,
    required this.onTap,
    this.editing = false,
    this.removalSelected = false,
    this.removalEnabled = true,
  });

  final OutboundInfo proxy;
  final bool selected;
  final GestureTapCallback? onTap;
  final bool editing;
  final bool removalSelected;
  final bool removalEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final countryTitle = _countryTitle(proxy);
    final cleanName = _cleanServerName(proxy.tagDisplay);
    final title = _titleLine(countryTitle, cleanName, proxy.tagDisplay);
    final details = _detailsSpans(theme, proxy, selected);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: removalSelected
          ? theme.colorScheme.errorContainer
          : selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () async => await ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: proxy),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(9, 7, 8, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IPCountryFlag(
                countryCode: proxy.ipinfo.countryCode,
                organization: proxy.ipinfo.org,
                size: 34,
                padding: const EdgeInsetsDirectional.only(end: 8),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFamily: PlatformUtils.isWindows ? FontFamily.emoji : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          fontFamily: PlatformUtils.isWindows ? FontFamily.emoji : null,
                        ),
                        children: details,
                      ),
                    ),
                  ],
                ),
              ),
              if (editing)
                Checkbox(
                  value: removalSelected,
                  onChanged: removalEnabled ? (_) => onTap?.call() : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _titleLine(String countryTitle, String cleanName, String fallback) {
    final name = cleanName.isEmpty ? fallback.trim() : cleanName;
    if (name.isEmpty) return countryTitle;

    final normalizedName = name.toLowerCase();
    final normalizedCountry = countryTitle.toLowerCase();
    if (normalizedName.contains(normalizedCountry) || countryTitle == 'Unknown country') {
      return name;
    }

    return '$countryTitle • $name';
  }

  List<InlineSpan> _detailsSpans(ThemeData theme, OutboundInfo proxy, bool selected) {
    final baseColor = selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant;
    final spans = <InlineSpan>[];

    void addText(String text, {Color? color, FontWeight? weight}) {
      if (spans.isNotEmpty) {
        spans.add(TextSpan(text: ' • ', style: TextStyle(color: baseColor.withOpacity(0.72))));
      }
      spans.add(TextSpan(text: text, style: TextStyle(color: color ?? baseColor, fontWeight: weight)));
    }

    if (selected) {
      addText('✓ Подключен', weight: FontWeight.w700);
    }

    final transport = _transportHint(proxy);
    if (transport.isNotEmpty) {
      addText(transport);
    }

    final type = proxy.type.trim();
    if (type.isNotEmpty) {
      final upperType = type.toUpperCase();
      if (transport.toUpperCase() != upperType) {
        addText(upperType);
      }
    }

    if (proxy.isSecure && !spans.any((span) => span.toPlainText().toLowerCase().contains('tls') || span.toPlainText().toLowerCase().contains('reality'))) {
      addText('Secure');
    }

    if (proxy.urlTestDelay != 0) {
      if (proxy.urlTestDelay > 65000) {
        addText('ping ×', color: _pingColor(theme, null), weight: FontWeight.w700);
      } else {
        addText('${proxy.urlTestDelay} ms', color: _pingColor(theme, proxy.urlTestDelay), weight: FontWeight.w700);
      }
    }

    if (proxy.isGroup) {
      final selectedTag = _cleanServerName(proxy.groupSelectedTagDisplay.trim());
      if (selectedTag.isNotEmpty) {
        addText('Balancer: $selectedTag');
      }
    }

    if (spans.isEmpty) {
      addText('—');
    }

    return spans;
  }

  Color _pingColor(ThemeData theme, int? ping) {
    if (ping == null || ping > 65000) {
      return Colors.red.shade600;
    }
    if (ping <= 60) {
      return Colors.green.shade600;
    }
    if (ping <= 150) {
      return Colors.amber.shade700;
    }
    return Colors.red.shade600;
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
