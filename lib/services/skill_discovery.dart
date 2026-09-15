import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/skill.dart';
import '../models/ssh_config.dart';
import 'host_key_trust_service.dart';
import 'ssh_client_factory.dart';

class SkillDiscovery {
  static const _cacheKey = 'cached_skills';

  /// Découvre les skills sur la machine distante via SSH.
  static Future<List<Skill>> discover(
    SshConfig config, {
    List<String> excludePatterns = const [],
    required HostKeyTrustService hostKeyTrust,
    required HostKeyConfirmation confirmHostKey,
  }) async {
    final socket = await SSHSocket.connect(
      config.host,
      config.port,
      timeout: const Duration(seconds: 10),
    );

    final client = SshClientFactory.create(
      socket: socket,
      host: config.host,
      port: config.port,
      username: config.username,
      password: config.password,
      hostKeyTrust: hostKeyTrust,
      confirmHostKey: confirmHostKey,
    );

    try {
      // Lister les skills depuis 3 sources :
      // 1. ~/.claude/commands/*.md (skills globales)
      // 2. ~/IdeaProjects/*/.claude/commands/*.md (skills projet format commands)
      // 3. ~/IdeaProjects/*/.claude/skills/*/SKILL.md (skills projet format skills)
      final result = await client.run(
        '{ '
        // 1. Global commands
        'ls ~/.claude/commands/*.md 2>/dev/null; '
        // 2. Project commands
        'for p in ~/IdeaProjects/*/; do '
        'ls "\$p.claude/commands/"*.md 2>/dev/null; '
        'done; '
        // 3. Project skills (SKILL.md in subdirs)
        'for p in ~/IdeaProjects/*/; do '
        'for s in "\$p.claude/skills/"*/SKILL.md; do '
        '[ -f "\$s" ] && echo "\$s"; '
        'done 2>/dev/null; '
        'done; '
        '} | sort -u | while read f; do '
        'echo "===FILE==="; '
        'dir=\$(dirname "\$f"); '
        'project=\$(echo "\$f" | grep -oP "IdeaProjects/\\K[^/]+" 2>/dev/null || echo ""); '
        // Déterminer le nom de la skill
        'if echo "\$f" | grep -q "/skills/"; then '
        // Format skills/nom-skill/SKILL.md -> nom du dossier parent
        '  name=\$(basename "\$dir"); '
        'else '
        // Format commands/nom.md -> basename sans .md
        '  name=\$(basename "\$f" .md); '
        'fi; '
        'if [ -n "\$project" ]; then echo "\$project:\$name"; else echo "\$name"; fi; '
        'echo "===PATH==="; echo "\$f"; '
        'head -20 "\$f"; '
        'echo "===HASARGS==="; '
        'grep -c "\\\$ARGUMENTS\\|arguments:" "\$f" 2>/dev/null || echo 0; '
        'done',
      );

      final output = utf8.decode(result);
      var skills = _parseOutput(output);

      // Filtrer les patterns exclus
      if (excludePatterns.isNotEmpty) {
        skills = skills.where((s) {
          final lower = s.id.toLowerCase();
          return !excludePatterns.any((p) => lower.contains(p.toLowerCase()));
        }).toList();
      }

      // Cache
      await _cacheSkills(skills);

      return skills;
    } finally {
      client.close();
    }
  }

  static List<Skill> _parseOutput(String output) {
    final skills = <Skill>[];
    final blocks = output.split('===FILE===');

    for (final block in blocks) {
      if (block.trim().isEmpty) continue;

      final lines = block.trim().split('\n');
      if (lines.isEmpty) continue;

      final rawId = lines[0].trim();
      if (rawId.isEmpty || rawId.startsWith('*') || rawId.startsWith('/'))
        continue;

      // Format: "projet:skill-name" ou "skill-name"
      String? project;
      String id;
      if (rawId.contains(':')) {
        project = rawId.split(':').first;
        id = rawId;
      } else {
        id = rawId;
      }

      // Extraire le filePath (ligne après ===PATH===)
      String? filePath;
      final pathIdx = lines.indexOf('===PATH===');
      if (pathIdx != -1 && pathIdx + 1 < lines.length) {
        filePath = lines[pathIdx + 1].trim();
        if (filePath.isEmpty) filePath = null;
      }

      // Extraire la description du frontmatter
      String description = '';
      bool inFrontmatter = false;
      int argCount = 0;

      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line == '===PATH===' || (pathIdx != -1 && i == pathIdx + 1))
          continue;

        if (line == '---' && !inFrontmatter) {
          inFrontmatter = true;
          continue;
        }
        if (line == '---' && inFrontmatter) {
          inFrontmatter = false;
          continue;
        }

        if (inFrontmatter && line.startsWith('description:')) {
          description = line
              .replaceFirst('description:', '')
              .trim()
              .replaceAll('"', '')
              .replaceAll("'", '');
        }
        // Format SKILL.md : arguments dans le frontmatter
        if (inFrontmatter && line.startsWith('arguments:')) {
          argCount++;
        }

        if (line == '===HASARGS===') {
          if (i + 1 < lines.length) {
            argCount = int.tryParse(lines[i + 1].trim()) ?? 0;
          }
          break;
        }
      }

      skills.add(
        Skill(
          id: id,
          description: description,
          hasArguments: argCount > 0,
          project: project,
          filePath: filePath,
        ),
      );
    }

    return skills;
  }

  /// Charge les skills depuis le cache.
  static Future<List<Skill>> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_cacheKey);
    if (raw == null) return [];
    return raw
        .map((e) => Skill.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> _cacheSkills(List<Skill> skills) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _cacheKey,
      skills.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }
}
