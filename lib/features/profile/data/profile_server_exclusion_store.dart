import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ProfileServerExclusionStore {
  ProfileServerExclusionStore(this._preferences);

  final SharedPreferences _preferences;

  String _key(String profileId) => 'excluded_server_tags_$profileId';

  Set<String> read(String profileId) {
    final raw = _preferences.getString(_key(profileId));
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.map((item) => item.toString()).where((tag) => tag.isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> write(String profileId, Set<String> tags) async {
    final sortedTags = tags.toList()..sort();
    await _preferences.setString(_key(profileId), jsonEncode(sortedTags));
  }

  Future<void> clear(String profileId) => _preferences.remove(_key(profileId));
}

class ServerExclusionResult {
  const ServerExclusionResult({
    required this.content,
    required this.removedTags,
    required this.remainingServerCount,
  });

  final String content;
  final Set<String> removedTags;
  final int remainingServerCount;
}

class ProfileServerConfigEditor {
  ProfileServerConfigEditor._();

  static const Set<String> _protectedTags = {
    'direct',
    'bypass',
    'block',
    'dns',
    'direct-fragment',
    'select',
    'lowest',
    'balance',
  };

  static const Set<String> _groupTypes = {'selector', 'urltest'};

  static ServerExclusionResult removeServers(String content, Set<String> excludedTags) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Profile config root must be a JSON object');
    }

    final rawOutbounds = decoded['outbounds'];
    if (rawOutbounds is! List) {
      throw const FormatException('Profile config does not contain an outbounds list');
    }

    final removedTags = <String>{};
    final remainingOutbounds = <dynamic>[];
    for (final outbound in rawOutbounds) {
      if (outbound is Map) {
        final tag = outbound['tag']?.toString() ?? '';
        final type = outbound['type']?.toString().toLowerCase() ?? '';
        final canRemove = tag.isNotEmpty && !_protectedTags.contains(tag.toLowerCase()) && !_groupTypes.contains(type);
        if (canRemove && excludedTags.contains(tag)) {
          removedTags.add(tag);
          continue;
        }
      }
      remainingOutbounds.add(outbound);
    }

    final remainingServerTags = remainingOutbounds
        .whereType<Map>()
        .where((outbound) {
          final tag = outbound['tag']?.toString().toLowerCase() ?? '';
          final type = outbound['type']?.toString().toLowerCase() ?? '';
          return tag.isNotEmpty && !_protectedTags.contains(tag) && !_groupTypes.contains(type);
        })
        .map((outbound) => outbound['tag'].toString())
        .toList();

    if (removedTags.isNotEmpty && remainingServerTags.isEmpty) {
      throw StateError('At least one server must remain in the subscription');
    }

    if (removedTags.isNotEmpty) {
      decoded['outbounds'] = remainingOutbounds;
      final remainingTags = remainingOutbounds
          .whereType<Map>()
          .map((outbound) => outbound['tag']?.toString() ?? '')
          .where((tag) => tag.isNotEmpty)
          .toSet();
      final fallbackOutbound = remainingTags.contains('select') ? 'select' : remainingServerTags.first;
      _removeReferences(decoded, removedTags, remainingServerTags, fallbackOutbound);
    }

    return ServerExclusionResult(
      content: const JsonEncoder.withIndent('  ').convert(decoded),
      removedTags: removedTags,
      remainingServerCount: remainingServerTags.length,
    );
  }

  static void _removeReferences(
    Object? value,
    Set<String> removedTags,
    List<String> remainingServerTags,
    String fallbackOutbound,
  ) {
    if (value is List) {
      value.removeWhere((item) => item is String && removedTags.contains(item));
      for (final item in value) {
        _removeReferences(item, removedTags, remainingServerTags, fallbackOutbound);
      }
      return;
    }

    if (value is! Map) return;
    for (final entry in value.entries.toList()) {
      final key = entry.key.toString();
      final child = entry.value;
      if (key == 'default' && child is String && removedTags.contains(child)) {
        value[entry.key] = remainingServerTags.first;
      } else if (key == 'outbound' && child is String && removedTags.contains(child)) {
        value[entry.key] = fallbackOutbound;
      } else {
        _removeReferences(child, removedTags, remainingServerTags, fallbackOutbound);
      }
    }
  }
}
