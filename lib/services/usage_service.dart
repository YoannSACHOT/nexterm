import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../models/ssh_config.dart';

class UsageData {
  final int sessionPercent;
  final String sessionReset;
  final int weeklyPercent;
  final int sonnetPercent;
  final int extraPercent;
  final int extraUsed;
  final int extraLimit;
  final bool extraEnabled;
  final int activeSessions;
  final DateTime fetchedAt;

  const UsageData({
    required this.sessionPercent,
    required this.sessionReset,
    required this.weeklyPercent,
    required this.sonnetPercent,
    required this.extraPercent,
    required this.extraUsed,
    required this.extraLimit,
    required this.extraEnabled,
    required this.activeSessions,
    required this.fetchedAt,
  });

  int get sessionRemaining => 100 - sessionPercent;
  int get weeklyRemaining => 100 - weeklyPercent;
}

class UsageService {
  /// Lit le cache d'usage depuis ~/.claude/usage-cache.json via SSH.
  static Future<UsageData?> fetch(SshConfig config) async {
    try {
      final socket = await SSHSocket.connect(
        config.host,
        config.port,
        timeout: const Duration(seconds: 5),
      );

      final client = SSHClient(
        socket,
        username: config.username,
        onPasswordRequest: () => config.password,
      );

      try {
        final result = await client.run(
          'echo "===USAGE==="; '
          'cat ~/.claude/usage-cache.json 2>/dev/null || echo "{}"; '
          'echo "===ACTIVE==="; '
          'pgrep -c -f "node.*claude" 2>/dev/null || echo 0',
        );

        final output = utf8.decode(result);
        final usagePart =
            _extractBetween(output, '===USAGE===', '===ACTIVE===');
        final activePart = output.split('===ACTIVE===').last.trim();

        final activeSessions =
            int.tryParse(activePart.split('\n').first.trim()) ?? 0;

        Map<String, dynamic> data;
        try {
          data = jsonDecode(usagePart.trim()) as Map<String, dynamic>;
        } catch (_) {
          return null;
        }

        if (data.isEmpty || data.containsKey('error')) return null;

        final fiveHour = data['five_hour'] as Map<String, dynamic>? ?? {};
        final sevenDay = data['seven_day'] as Map<String, dynamic>? ?? {};
        final sonnet =
            data['seven_day_sonnet'] as Map<String, dynamic>? ?? {};
        final extra = data['extra_usage'] as Map<String, dynamic>? ?? {};

        // Calculer le temps restant pour le reset de session
        String sessionReset = '';
        final resetAt = fiveHour['resets_at'] as String?;
        if (resetAt != null) {
          try {
            final resetTime = DateTime.parse(resetAt);
            final diff = resetTime.difference(DateTime.now().toUtc());
            if (diff.isNegative) {
              sessionReset = 'reset';
            } else if (diff.inHours > 0) {
              sessionReset =
                  '${diff.inHours}h${(diff.inMinutes % 60).toString().padLeft(2, '0')}';
            } else {
              sessionReset = '${diff.inMinutes}min';
            }
          } catch (_) {}
        }

        return UsageData(
          sessionPercent: (fiveHour['utilization'] as num?)?.toInt() ?? 0,
          sessionReset: sessionReset,
          weeklyPercent: (sevenDay['utilization'] as num?)?.toInt() ?? 0,
          sonnetPercent: (sonnet['utilization'] as num?)?.toInt() ?? 0,
          extraPercent: (extra['utilization'] as num?)?.toInt() ?? 0,
          extraUsed: (extra['used_credits'] as num?)?.toInt() ?? 0,
          extraLimit: (extra['monthly_limit'] as num?)?.toInt() ?? 0,
          extraEnabled: extra['is_enabled'] as bool? ?? false,
          activeSessions: activeSessions,
          fetchedAt: DateTime.now(),
        );
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  static String _extractBetween(String text, String start, String end) {
    final startIdx = text.indexOf(start);
    final endIdx = text.indexOf(end);
    if (startIdx == -1 || endIdx == -1) return '{}';
    return text.substring(startIdx + start.length, endIdx);
  }
}
