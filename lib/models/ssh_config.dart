import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/secure_storage_service.dart';

class SshConfig {
  String host;
  int port;
  String username;
  String password;
  List<String> excludePatterns;

  SshConfig({
    this.host = '',
    this.port = 22,
    this.username = '',
    this.password = '',
    List<String>? excludePatterns,
  }) : excludePatterns = excludePatterns ?? ['bmad'];

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'excludePatterns': excludePatterns,
      };

  factory SshConfig.fromJson(Map<String, dynamic> json) => SshConfig(
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 22,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        excludePatterns: (json['excludePatterns'] as List<dynamic>?)
                ?.cast<String>() ??
            ['bmad'],
      );

  static const passwordStorageKey = 'ssh.config.password';

  static Future<SshConfig> load({SecretStore? secretStore}) async {
    final store = secretStore ?? defaultSecretStore;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('ssh_config');
    if (raw != null) {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final config = SshConfig.fromJson(json);
      final legacyPassword = config.password;
      var password = await store.read(passwordStorageKey);
      if (password == null && legacyPassword.isNotEmpty) {
        await store.write(passwordStorageKey, legacyPassword);
        password = legacyPassword;
      }
      config.password = password ?? '';
      if (json.containsKey('password')) {
        await prefs.setString('ssh_config', jsonEncode(config.toJson()));
      }
      return config;
    }
    return SshConfig(password: await store.read(passwordStorageKey) ?? '');
  }

  Future<void> save({SecretStore? secretStore}) async {
    final store = secretStore ?? defaultSecretStore;
    if (password.isEmpty) {
      await store.delete(passwordStorageKey);
    } else {
      await store.write(passwordStorageKey, password);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ssh_config', jsonEncode(toJson()));
  }

  bool shouldExclude(String skillId) {
    final lower = skillId.toLowerCase();
    return excludePatterns
        .any((p) => lower.contains(p.toLowerCase()));
  }
}
