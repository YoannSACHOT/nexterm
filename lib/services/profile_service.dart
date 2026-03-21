import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ssh_profile.dart';

class ProfileService {
  static const _key = 'ssh_profiles';

  Future<List<SshProfile>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw.map((e) => SshProfile.decode(e)).toList();
  }

  Future<void> saveProfiles(List<SshProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, profiles.map((p) => p.encode()).toList());
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
