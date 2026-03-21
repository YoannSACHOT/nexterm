import 'package:dartssh2/dartssh2.dart';

enum SkillStatus { connecting, running, done, error }

class SkillSession {
  final String id;
  final String skillId;
  final String skillName;
  final DateTime startedAt;
  SkillStatus status;
  SSHClient? sshClient;
  SSHSession? sshSession;
  final StringBuffer output = StringBuffer();
  String? errorMessage;

  SkillSession({
    required this.id,
    required this.skillId,
    required this.skillName,
    required this.startedAt,
    this.status = SkillStatus.connecting,
  });

  String get lastLines {
    final lines = output.toString().split('\n');
    final last = lines.length > 5 ? lines.sublist(lines.length - 5) : lines;
    return last.join('\n').trim();
  }

  void dispose() {
    sshSession?.close();
    sshClient?.close();
  }
}
