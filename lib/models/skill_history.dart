import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SkillHistoryEntry {
  final String skillId;
  final String skillName;
  final String? arguments;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final bool success;
  final String? output;

  SkillHistoryEntry({
    required this.skillId,
    required this.skillName,
    this.arguments,
    required this.startedAt,
    this.finishedAt,
    required this.success,
    this.output,
  });

  /// Nettoie l'output des codes ANSI pour affichage texte.
  static String stripAnsi(String text) {
    return text
        .replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '')
        .replaceAll(RegExp(r'\x1B\][^\x07]*\x07'), '')
        .replaceAll(RegExp(r'\x1B[()][AB012]'), '')
        .replaceAll(RegExp(r'\x1B\[[\?]?[0-9;]*[hlm]'), '')
        .replaceAll('\r', '');
  }

  Duration? get duration => finishedAt?.difference(startedAt);

  String get durationStr {
    final d = duration;
    if (d == null) return '—';
    if (d.inMinutes >= 60) {
      return '${d.inHours}h${(d.inMinutes % 60).toString().padLeft(2, '0')}';
    }
    if (d.inSeconds >= 60) {
      return '${d.inMinutes}m${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
    }
    return '${d.inSeconds}s';
  }

  Map<String, dynamic> toJson() => {
    'skillId': skillId,
    'skillName': skillName,
    'startedAt': startedAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'success': success,
  };

  factory SkillHistoryEntry.fromJson(Map<String, dynamic> json) =>
      SkillHistoryEntry(
        skillId: json['skillId'] as String,
        skillName: json['skillName'] as String,
        arguments: null,
        startedAt: DateTime.parse(json['startedAt'] as String),
        finishedAt: json['finishedAt'] != null
            ? DateTime.parse(json['finishedAt'] as String)
            : null,
        success: json['success'] as bool? ?? true,
        output: null,
      );
}

class SkillHistoryService {
  static const _key = 'skill_history';
  static const _maxEntries = 50;

  static Future<List<SkillHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final entries = raw
        .map(
          (e) =>
              SkillHistoryEntry.fromJson(jsonDecode(e) as Map<String, dynamic>),
        )
        .toList();
    final sanitized = entries
        .map((entry) => jsonEncode(entry.toJson()))
        .toList();
    if (!_sameValues(raw, sanitized)) {
      await prefs.setStringList(_key, sanitized);
    }
    return entries.reversed.toList(); // Plus récent en premier
  }

  /// Retourne la dernière entrée pour une skill donnée (avec output).
  static Future<SkillHistoryEntry?> lastForSkill(String skillId) async {
    final entries = await load();
    for (final e in entries) {
      if (e.skillId == skillId && e.output != null && e.output!.isNotEmpty) {
        return e;
      }
    }
    return null;
  }

  static Future<void> add(SkillHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(entry.toJson()));
    // Garder les N dernières entrées
    if (raw.length > _maxEntries) {
      raw.removeRange(0, raw.length - _maxEntries);
    }
    await prefs.setStringList(_key, raw);
  }

  static bool _sameValues(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
