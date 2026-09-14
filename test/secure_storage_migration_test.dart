import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/skill_history.dart';
import 'package:nexterm/models/ssh_config.dart';
import 'package:nexterm/services/profile_service.dart';
import 'package:nexterm/services/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy config password migrates before plaintext is removed', () async {
    SharedPreferences.setMockInitialValues({
      'ssh_config': jsonEncode({
        'host': 'server',
        'port': 22,
        'username': 'user',
        'password': 'legacy-secret',
      }),
    });
    final store = MemorySecretStore();

    final config = await SshConfig.load(secretStore: store);

    expect(config.password, 'legacy-secret');
    expect(store.values['ssh.config.password'], 'legacy-secret');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ssh_config'), isNot(contains('legacy-secret')));
    expect(prefs.getString('ssh_config'), isNot(contains('password')));
  });

  test('failed secure write preserves legacy config password', () async {
    SharedPreferences.setMockInitialValues({
      'ssh_config': jsonEncode({
        'host': 'server',
        'username': 'user',
        'password': 'must-survive',
      }),
    });

    await expectLater(
      SshConfig.load(secretStore: FailingSecretStore()),
      throwsStateError,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ssh_config'), contains('must-survive'));
  });

  test('legacy profile passwords migrate and metadata stays usable', () async {
    SharedPreferences.setMockInitialValues({
      'ssh_profiles': [
        jsonEncode({
          'id': 'profile-1',
          'name': 'Prod',
          'host': 'server',
          'username': 'user',
          'password': 'profile-secret',
        }),
      ],
    });
    final store = MemorySecretStore();

    final profiles = await ProfileService(secretStore: store).loadProfiles();

    expect(profiles.single.password, 'profile-secret');
    expect(store.values['ssh.profile.profile-1.password'], 'profile-secret');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('ssh_profiles')!.single,
      isNot(contains('profile-secret')),
    );
    expect(
      prefs.getStringList('ssh_profiles')!.single,
      isNot(contains('password')),
    );
  });

  test(
    'legacy history is rewritten without arguments or terminal output',
    () async {
      SharedPreferences.setMockInitialValues({
        'skill_history': [
          jsonEncode({
            'skillId': 'deploy',
            'skillName': 'Deploy',
            'arguments': '--token secret',
            'startedAt': '2026-09-14T01:00:00.000Z',
            'finishedAt': '2026-09-14T01:01:00.000Z',
            'success': true,
            'output': 'terminal secret',
          }),
        ],
      });

      final entries = await SkillHistoryService.load();

      expect(entries.single.arguments, isNull);
      expect(entries.single.output, isNull);
      final prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getStringList('skill_history')!.single;
      expect(persisted, isNot(contains('arguments')));
      expect(persisted, isNot(contains('output')));
      expect(persisted, isNot(contains('secret')));
    },
  );

  test('history retention keeps only fifty metadata entries', () async {
    SharedPreferences.setMockInitialValues({});
    for (var i = 0; i < 51; i++) {
      await SkillHistoryService.add(
        SkillHistoryEntry(
          skillId: 'skill-$i',
          skillName: 'Skill $i',
          arguments: 'sensitive-$i',
          startedAt: DateTime.utc(2026, 9, 14, 1, i),
          success: true,
          output: 'raw-$i',
        ),
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final persisted = prefs.getStringList('skill_history')!;
    expect(persisted, hasLength(50));
    expect(persisted.join(), isNot(contains('sensitive')));
    expect(persisted.join(), isNot(contains('raw-')));
  });
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class FailingSecretStore implements SecretStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) =>
      throw StateError('secure storage unavailable');
}
