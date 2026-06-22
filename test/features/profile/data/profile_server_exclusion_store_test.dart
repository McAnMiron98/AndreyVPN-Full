import 'dart:convert';

import 'package:andreyvpn/features/profile/data/profile_server_exclusion_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes selected server and references from selector groups', () {
    final source = jsonEncode({
      'outbounds': [
        {
          'type': 'selector',
          'tag': 'select',
          'outbounds': ['server-a', 'server-b'],
          'default': 'server-a',
        },
        {'type': 'vless', 'tag': 'server-a'},
        {'type': 'vless', 'tag': 'server-b'},
        {'type': 'direct', 'tag': 'direct'},
      ],
    });

    final result = ProfileServerConfigEditor.removeServers(source, {'server-a'});
    final config = jsonDecode(result.content) as Map<String, dynamic>;
    final outbounds = config['outbounds'] as List<dynamic>;
    final selector = outbounds.first as Map<String, dynamic>;

    expect(result.removedTags, {'server-a'});
    expect(result.remainingServerCount, 1);
    expect(outbounds.where((item) => item['tag'] == 'server-a'), isEmpty);
    expect(selector['outbounds'], ['server-b']);
    expect(selector['default'], 'server-b');
  });

  test('does not allow deleting the last server', () {
    final source = jsonEncode({
      'outbounds': [
        {
          'type': 'selector',
          'tag': 'select',
          'outbounds': ['server-a'],
        },
        {'type': 'vless', 'tag': 'server-a'},
      ],
    });

    expect(
      () => ProfileServerConfigEditor.removeServers(source, {'server-a'}),
      throwsStateError,
    );
  });
}
