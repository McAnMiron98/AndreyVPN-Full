import 'dart:convert';

import 'package:andreyvpn/features/profile/data/profile_server_exclusion_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads legacy string exclusions as hidden servers', () async {
    SharedPreferences.setMockInitialValues({
      'excluded_server_tags_profile-a': jsonEncode(['server-b', 'server-a']),
    });
    final preferences = await SharedPreferences.getInstance();
    final store = ProfileServerExclusionStore(preferences);

    final servers = store.read('profile-a');

    expect(servers.map((server) => server.tag), ['server-a', 'server-b']);
    expect(servers.map((server) => server.name), ['server-a', 'server-b']);
  });

  test('persists hidden server display data', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = ProfileServerExclusionStore(preferences);
    final hiddenAt = DateTime.utc(2026, 6, 22, 12);

    await store.write('profile-a', [
      HiddenServer(tag: 'server-a', name: 'Germany, Frankfurt', hiddenAt: hiddenAt),
    ]);
    final servers = store.read('profile-a');

    expect(servers, hasLength(1));
    expect(servers.single.tag, 'server-a');
    expect(servers.single.name, 'Germany, Frankfurt');
    expect(servers.single.hiddenAt, hiddenAt);
  });

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
