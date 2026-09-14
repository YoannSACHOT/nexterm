import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_profile.dart';
import '../models/terminal_tab.dart';
import 'host_key_trust_service.dart';
import 'ssh_client_factory.dart';

class SshService {
  Future<TerminalTab> connect({
    required SshProfile profile,
    required String tabId,
    required String title,
    required HostKeyTrustService hostKeyTrust,
    required HostKeyConfirmation confirmHostKey,
    String? sessionName,
    void Function(String)? onError,
    void Function()? onDone,
  }) async {
    final terminal = Terminal(maxLines: 10000);
    final tab = TerminalTab(
      id: tabId,
      title: title,
      terminal: terminal,
      profileId: profile.id,
      isConnecting: true,
    );

    terminal.write('Connexion à ${profile.host}:${profile.port}...\r\n');

    try {
      final socket = await SSHSocket.connect(
        profile.host,
        profile.port,
        timeout: const Duration(seconds: 10),
      );

      final client = SshClientFactory.create(
        socket: socket,
        host: profile.host,
        port: profile.port,
        username: profile.username,
        password: profile.password,
        hostKeyTrust: hostKeyTrust,
        confirmHostKey: confirmHostKey,
      );

      tab.sshClient = client;
      tab.isConnecting = false;
      tab.isConnected = true;

      terminal.write('Connecté !\r\n');

      final session = await client.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );

      tab.session = session;

      // Terminal -> SSH
      terminal.onOutput = (data) {
        session.write(utf8.encode(data) as Uint8List);
      };

      // Terminal resize -> SSH
      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        session.resizeTerminal(width, height, pixelWidth, pixelHeight);
      };

      // SSH -> Terminal
      session.stdout.listen(
        (data) {
          terminal.write(utf8.decode(data, allowMalformed: true));
        },
        onDone: () {
          tab.isConnected = false;
          terminal.write('\r\n[Connexion fermée]\r\n');
          onDone?.call();
        },
        onError: (e) {
          tab.isConnected = false;
          terminal.write('\r\n[Erreur: $e]\r\n');
          onError?.call(e.toString());
        },
      );

      // Commande de démarrage (construite avec les options Claude)
      final command = profile.buildCommand(sessionName);
      if (command.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 500));
        session.write(utf8.encode('$command\n') as Uint8List);
      }
    } catch (e) {
      tab.isConnecting = false;
      tab.isConnected = false;
      terminal.write('\r\n[Erreur de connexion: $e]\r\n');
      onError?.call(e.toString());
    }

    return tab;
  }

  /// Test rapide de connexion SSH (ping)
  Future<bool> testConnection(
    SshProfile profile, {
    required HostKeyTrustService hostKeyTrust,
    required HostKeyConfirmation confirmHostKey,
  }) async {
    try {
      final socket = await SSHSocket.connect(
        profile.host,
        profile.port,
        timeout: const Duration(seconds: 5),
      );
      final client = SshClientFactory.create(
        socket: socket,
        host: profile.host,
        port: profile.port,
        username: profile.username,
        password: profile.password,
        hostKeyTrust: hostKeyTrust,
        confirmHostKey: confirmHostKey,
      );
      client.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}
