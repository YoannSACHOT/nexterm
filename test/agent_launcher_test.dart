import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/agent_launcher.dart';

void main() {
  late Directory home;
  Future<void> script(String path, String content) async {
    final file = File('${home.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString('#!/bin/sh\n$content\n');
    await Process.run('chmod', ['+x', file.path]);
  }

  Future<ProcessResult> run(AgentLauncher launcher) => Process.run(
    '/bin/sh',
    ['-c', launcher.buildCommand(cycleLockDirectory: home.path)],
    environment: {'HOME': home.path},
  ).timeout(const Duration(seconds: 8));

  setUp(() async {
    home = await Directory.systemTemp.createTemp('nexterm-agent-');
    for (final agent in CodingAgent.values) {
      await script(
        '.local/bin/${agent.executable}',
        r'''printf '%s\n' "$@" > "$HOME/args"
exit 0''',
      );
    }
    await script(
      '.claude/hooks/session-closable.sh',
      "echo 'VERT : tout est versionné.'",
    );
  });
  tearDown(() async => home.delete(recursive: true));

  for (final agent in CodingAgent.values) {
    test(
      '${agent.label} opens its own interactive CLI without prompt',
      () async {
        final result = await run(AgentLauncher(agent));
        expect(result.exitCode, 0);
        final args = await File('${home.path}/args').readAsLines();
        expect(
          args,
          agent == CodingAgent.codex
              ? ['']
              : ['--dangerously-skip-permissions'],
        );
      },
    );
    test(
      '${agent.label} receives exact autonomous prompt and closes on green',
      () async {
        final result = await run(AgentLauncher(agent, autonomous: true));
        expect(result.exitCode, 0);
        expect(result.stdout, contains('VERT :'));
        final args = await File('${home.path}/args').readAsLines();
        expect(args.last, AgentLauncher.prompt);
        expect(args, contains(agent == CodingAgent.codex ? 'exec' : '-p'));
      },
    );
  }

  const auto = AgentLauncher(CodingAgent.codex, autonomous: true);
  test('a silent hook exiting zero cannot authorize closure', () async {
    await script('.claude/hooks/session-closable.sh', 'exit 0');
    expect((await run(auto)).exitCode, 78);
  });
  test('missing hook prevents starting autonomous work', () async {
    await File('${home.path}/.claude/hooks/session-closable.sh').delete();
    expect((await run(auto)).exitCode, 78);
    expect(File('${home.path}/args').existsSync(), isFalse);
  });
  test('failed CLI never closes even when hook is green', () async {
    await script('.local/bin/codex', 'exit 23');
    expect((await run(auto)).exitCode, 23);
  });
  test('hook error and malformed red both keep session', () async {
    for (final content in [
      'exit 2',
      'echo invalid; exit 1',
      "echo 'VERT : bad'; exit 1",
    ]) {
      await script('.claude/hooks/session-closable.sh', content);
      expect((await run(auto)).exitCode, 78);
    }
  });
  test('red remains open then green closes without rerunning CLI', () async {
    await script('.claude/hooks/session-closable.sh', r'''
if [ ! -f "$HOME/green" ]; then echo 'ROUGE : travail non poussé'; exit 1; fi
echo 'VERT : sauvegardé'
''');
    final p = await Process.start(
      '/bin/sh',
      ['-c', auto.buildCommand(cycleLockDirectory: home.path)],
      environment: {'HOME': home.path},
    );
    addTearDown(() => p.kill());
    final lines = p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final waiting = lines.firstWhere((line) => line.contains('En attente'));
    bool exited = false;
    p.exitCode.then((_) => exited = true);
    await waiting.timeout(const Duration(seconds: 3));
    expect(exited, isFalse);
    p.kill();
    await p.exitCode;
    // Accelerate the wait only in the isolated fake server environment.
    await script('.local/bin/sleep', r'touch "$HOME/green"');
    final result = await run(auto);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('ROUGE :'));
    expect(result.stdout, contains('VERT :'));
  });
  test('active ops mutex prevents green closure until removed', () async {
    await Directory('${home.path}/ops-issues.lock').create();
    await script('.local/bin/sleep', r'rmdir "$HOME/ops-issues.lock"');
    final result = await run(auto);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('Un cycle ops est encore actif'));
  });
  test('only autonomous successful exits remove the tab', () {
    for (final launcher in AgentLauncher.cards) {
      expect(launcher.shouldClose(0), launcher.autonomous);
      for (final code in [null, -1, 1, 78, 255]) {
        expect(launcher.shouldClose(code), isFalse);
      }
    }
  });
}
