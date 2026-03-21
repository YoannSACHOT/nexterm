import 'package:flutter/material.dart';

class Skill {
  final String id; // "skill-name" ou "projet:skill-name"
  final String description;
  final bool hasArguments;
  final String? project; // nom du projet si skill projet-level
  final String? filePath; // chemin absolu du fichier skill sur le serveur

  const Skill({
    required this.id,
    required this.description,
    this.hasArguments = false,
    this.project,
    this.filePath,
  });

  /// Nom affiché (sans le préfixe projet).
  String get skillId => id.contains(':') ? id.split(':').last : id;

  String get name {
    final base = skillId
        .split('-')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
    if (project != null) return '$base ($project)';
    return base;
  }

  IconData get icon {
    if (id.contains('promo')) return Icons.campaign;
    if (id.contains('stats')) return Icons.bar_chart;
    if (id.contains('audit')) return Icons.security;
    if (id.contains('facture')) return Icons.receipt_long;
    return Icons.extension;
  }

  Color get color {
    if (id.contains('esprit') && id.contains('promo')) return const Color(0xFF1565C0);
    if (id.contains('lyroes')) return const Color(0xFF6A1B9A);
    if (id.contains('pistemploi')) return const Color(0xFF2E7D32);
    if (id.contains('stats')) return const Color(0xFFE65100);
    if (id.contains('audit')) return const Color(0xFFC62828);
    if (id.contains('facture')) return const Color(0xFF00695C);
    // Couleur par hash pour les skills inconnues
    final hash = id.hashCode.abs();
    final colors = [
      const Color(0xFF1565C0),
      const Color(0xFF6A1B9A),
      const Color(0xFF2E7D32),
      const Color(0xFFE65100),
      const Color(0xFFC62828),
      const Color(0xFF00695C),
      const Color(0xFF4527A0),
      const Color(0xFF283593),
    ];
    return colors[hash % colors.length];
  }

  String buildCommand(String? arguments) {
    final cmd = '/$skillId';
    if (arguments != null && arguments.trim().isNotEmpty) {
      return '$cmd ${arguments.trim()}';
    }
    return cmd;
  }

  /// Répertoire de travail pour cette skill.
  String? get workingDirectory =>
      project != null ? '~/IdeaProjects/$project' : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'hasArguments': hasArguments,
        'project': project,
        'filePath': filePath,
      };

  factory Skill.fromJson(Map<String, dynamic> json) => Skill(
        id: json['id'] as String,
        description: json['description'] as String? ?? '',
        hasArguments: json['hasArguments'] as bool? ?? false,
        project: json['project'] as String?,
        filePath: json['filePath'] as String?,
      );
}
