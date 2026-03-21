import 'dart:convert';

class SshProfile {
  final String id;
  String name;
  String host;
  int port;
  String username;
  String password;
  String? startupCommand;
  bool skipPermissions;
  String? claudeModel;
  String? workingDirectory;
  String? claudeExtraArgs;

  SshProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    required this.password,
    this.startupCommand,
    this.skipPermissions = true,
    this.claudeModel,
    this.workingDirectory,
    this.claudeExtraArgs,
  });

  /// Construit la commande claude-session complète.
  String buildCommand(String? sessionName) {
    final parts = <String>[];

    // cd dans le répertoire de travail si spécifié
    if (workingDirectory != null && workingDirectory!.isNotEmpty) {
      parts.add('cd ${workingDirectory!}');
    }

    // Construire la commande claude
    final claudeArgs = <String>[];
    if (skipPermissions) {
      claudeArgs.add('--dangerously-skip-permissions');
    }
    if (claudeModel != null && claudeModel!.isNotEmpty) {
      claudeArgs.add('--model ${claudeModel!}');
    }
    if (claudeExtraArgs != null && claudeExtraArgs!.isNotEmpty) {
      claudeArgs.add(claudeExtraArgs!);
    }

    final claudeFlags = claudeArgs.join(' ');

    if (startupCommand != null && startupCommand!.isNotEmpty) {
      var cmd = startupCommand!;
      if (sessionName != null && sessionName.isNotEmpty) {
        // Remplacer ou ajouter le nom de session
        if (cmd.contains('claude-session')) {
          cmd = 'claude-session $sessionName';
        } else {
          cmd = '$cmd $sessionName';
        }
      }
      // Injecter les flags claude dans la commande tmux
      if (claudeFlags.isNotEmpty && cmd.contains('claude-session')) {
        // claude-session lance "claude" dans tmux, on passe les args via env
        parts.add('export CLAUDE_ARGS="$claudeFlags"');
      }
      parts.add(cmd);
    } else if (claudeFlags.isNotEmpty) {
      parts.add('export PATH="\$HOME/.local/bin:\$PATH" && claude $claudeFlags');
    }

    return parts.join(' && ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'startupCommand': startupCommand,
        'skipPermissions': skipPermissions,
        'claudeModel': claudeModel,
        'workingDirectory': workingDirectory,
        'claudeExtraArgs': claudeExtraArgs,
      };

  factory SshProfile.fromJson(Map<String, dynamic> json) => SshProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        host: json['host'] as String,
        port: json['port'] as int? ?? 22,
        username: json['username'] as String,
        password: json['password'] as String,
        startupCommand: json['startupCommand'] as String?,
        skipPermissions: json['skipPermissions'] as bool? ?? false,
        claudeModel: json['claudeModel'] as String?,
        workingDirectory: json['workingDirectory'] as String?,
        claudeExtraArgs: json['claudeExtraArgs'] as String?,
      );

  String encode() => jsonEncode(toJson());

  factory SshProfile.decode(String source) =>
      SshProfile.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
