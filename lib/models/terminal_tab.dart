import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

class TerminalTab {
  final String id;
  String title;
  final Terminal terminal;
  SSHClient? sshClient;
  SSHSession? session;
  bool isConnected;
  bool isConnecting;
  final String profileId;

  TerminalTab({
    required this.id,
    required this.title,
    required this.terminal,
    required this.profileId,
    this.sshClient,
    this.session,
    this.isConnected = false,
    this.isConnecting = false,
  });

  void dispose() {
    session?.close();
    sshClient?.close();
  }
}
