import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ssh_profile.dart';
import 'secure_storage_service.dart';

class ProfileService {
  static const _key = 'ssh_profiles';
  final SecretStore _secretStore;

  ProfileService({SecretStore? secretStore})
    : _secretStore = secretStore ?? defaultSecretStore;

  String _passwordKey(String id) => 'ssh.profile.$id.password';

  Future<List<SshProfile>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final profiles = <SshProfile>[];
    var containsLegacySecrets = false;

    for (final encoded in raw) {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final profile = SshProfile.fromJson(json);
      final legacyPassword = profile.password;
      var password = await _secretStore.read(_passwordKey(profile.id));
      if (password == null && legacyPassword.isNotEmpty) {
        await _secretStore.write(_passwordKey(profile.id), legacyPassword);
        password = legacyPassword;
      }
      profile.password = password ?? '';
      containsLegacySecrets |= json.containsKey('password');
      profiles.add(profile);
    }

    if (containsLegacySecrets) {
      await prefs.setStringList(
        _key,
        profiles.map((profile) => profile.encode()).toList(),
      );
    }
    return profiles;
  }

  Future<void> saveProfiles(List<SshProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    final previousIds = (prefs.getStringList(_key) ?? [])
        .map((encoded) => jsonDecode(encoded) as Map<String, dynamic>)
        .map((json) => json['id'] as String)
        .toSet();

    for (final profile in profiles) {
      final key = _passwordKey(profile.id);
      if (profile.password.isEmpty) {
        await _secretStore.delete(key);
      } else {
        await _secretStore.write(key, profile.password);
      }
    }
    await prefs.setStringList(_key, profiles.map((p) => p.encode()).toList());

    final currentIds = profiles.map((profile) => profile.id).toSet();
    for (final removedId in previousIds.difference(currentIds)) {
      await _secretStore.delete(_passwordKey(removedId));
    }
  }

  Future<void> addProfile(SshProfile profile) async {
    final profiles = await loadProfiles();
    profiles.add(profile);
    await saveProfiles(profiles);
  }

  Future<void> updateProfile(SshProfile profile) async {
    final profiles = await loadProfiles();
    final index = profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      profiles[index] = profile;
      await saveProfiles(profiles);
    }
  }

  Future<void> deleteProfile(String id) async {
    final profiles = await loadProfiles();
    profiles.removeWhere((p) => p.id == id);
    await saveProfiles(profiles);
  }
}
