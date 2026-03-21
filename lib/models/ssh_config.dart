import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        'password': password,
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

  static Future<SshConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('ssh_config');
    if (raw != null) {
      return SshConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    // Premier lancement : charger depuis config.local.json si présent
    try {
      final local = await rootBundle.loadString('config.local.json');
      final config =
          SshConfig.fromJson(jsonDecode(local) as Map<String, dynamic>);
      await config.save();
      return config;
    } catch (_) {
      return SshConfig();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ssh_config', jsonEncode(toJson()));
  }

  bool shouldExclude(String skillId) {
    final lower = skillId.toLowerCase();
    return excludePatterns
        .any((p) => lower.contains(p.toLowerCase()));
  }
}
