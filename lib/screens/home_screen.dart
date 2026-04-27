import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../models/skill.dart';
import '../models/skill_session.dart';
import '../models/ssh_config.dart';
import '../services/connectivity_service.dart';
import '../services/foreground_service.dart';
import '../services/notification_service.dart';
import '../services/skill_discovery.dart';
import '../models/skill_history.dart';
import '../services/usage_service.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _connectivity = ConnectivityService();
  ConnectivityStatus? _status;
  bool _isChecking = false;
  SshConfig _config = SshConfig();

  // Skills chargées dynamiquement
  List<Skill> _skills = [];
  bool _isLoadingSkills = false;

  // Usage
  UsageData? _usage;
  Timer? _usageTimer;

  // Sessions en cours
  final List<SkillSession> _sessions = [];
  String? _activeSessionId;
  final Map<String, Terminal> _terminals = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _config = await SshConfig.load();
    // Charger le cache d'abord
    _skills = await SkillDiscovery.loadCached();
    setState(() {});
    // Puis vérifier la connectivité et recharger
    await _checkConnectivity();
    if (_status?.allGood == true) {
      _discoverSkills();
      _fetchUsage();
      // Refresh usage toutes les 2 minutes
      _usageTimer = Timer.periodic(
        const Duration(minutes: 2),
        (_) => _fetchUsage(),
      );
    }
  }

  @override
  void dispose() {
    _usageTimer?.cancel();
    for (final s in _sessions) {
      s.dispose();
    }
    ForegroundService.stopAll();
    super.dispose();
  }

  Future<void> _fetchUsage() async {
    final usage = await UsageService.fetch(_config);
    if (mounted && usage != null) {
      setState(() => _usage = usage);
    }
  }

  Future<void> _checkConnectivity() async {
    setState(() => _isChecking = true);
    final status = await _connectivity.checkStatus(_config.host, _config.port);
    setState(() {
      _status = status;
      _isChecking = false;
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _checkConnectivity(),
      _fetchUsage(),
      _discoverSkills(),
    ]);
  }

  Future<void> _discoverSkills() async {
    setState(() => _isLoadingSkills = true);
    try {
      final skills = await SkillDiscovery.discover(
        _config,
        excludePatterns: _config.excludePatterns,
      );
      setState(() {
        _skills = skills;
        _isLoadingSkills = false;
      });
    } catch (e) {
      setState(() => _isLoadingSkills = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  Future<void> _launchSkill(Skill skill, [String? arguments]) async {
    final command = skill.buildCommand(arguments);
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final startTime = DateTime.now();

    final session = SkillSession(
      id: sessionId,
      skillId: skill.id,
      skillName: skill.name,
      startedAt: startTime,
    );

    final terminal = Terminal(maxLines: 10000);
    _terminals[sessionId] = terminal;

    setState(() {
      _sessions.add(session);
      _activeSessionId = sessionId;
    });

    _syncForegroundService(status: skill.name);

    terminal.write('Lancement de ${skill.name}...\r\n');

    try {
      final socket = await SSHSocket.connect(
        _config.host,
        _config.port,
        timeout: const Duration(seconds: 10),
      );

      final client = SSHClient(
        socket,
        username: _config.username,
        onPasswordRequest: () => _config.password,
      );

      session.sshClient = client;
      setState(() => session.status = SkillStatus.running);

      terminal.write('Connecté. Exécution de $command...\r\n\r\n');

      // Utiliser execute() au lieu de shell() :
      // - La session se ferme automatiquement quand la commande termine
      // - Pas besoin de "; exit"
      // - Output propre sans bruit du shell (prompt, bannière, etc.)
      final dir = skill.workingDirectory;
      final String baseCmd;
      if (skill.filePath != null) {
        // Lire le contenu du fichier skill et le passer via stdin
        // Utiliser cat | claude -p - pour éviter les problèmes d'échappement
        final filePath = skill.filePath!;
        if (arguments != null && arguments.trim().isNotEmpty) {
          baseCmd =
              '{ echo "Arguments: ${arguments.trim()}"; echo "---"; cat $filePath; } | claude --dangerously-skip-permissions -p -';
        } else {
          baseCmd =
              'cat $filePath | claude --dangerously-skip-permissions -p -';
        }
      } else {
        // Fallback : passer la commande slash directement
        baseCmd = 'claude --dangerously-skip-permissions -p "$command"';
      }
      final pathSetup = 'export PATH="\$HOME/.local/bin:\$PATH"';
      final fullCmd = dir != null
          ? '$pathSetup && cd $dir && $baseCmd'
          : '$pathSetup && $baseCmd';

      final sshSession = await client.execute(fullCmd);

      session.sshSession = sshSession;

      // stdout -> terminal + capture output
      final stdoutDone = Completer<void>();
      sshSession.stdout.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          terminal.write(text);
          session.output.write(text);
        },
        onDone: () => stdoutDone.complete(),
      );

      // stderr -> terminal + capture output
      final stderrDone = Completer<void>();
      sshSession.stderr.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          terminal.write(text);
          session.output.write(text);
        },
        onDone: () => stderrDone.complete(),
      );

      // Attendre que les streams soient terminés + session fermée
      await Future.wait([stdoutDone.future, stderrDone.future, sshSession.done]);
      final exitCode = sshSession.exitCode ?? -1;
      final success = exitCode == 0;

      terminal.write('\r\n[Session terminée — code $exitCode]\r\n');
      setState(() => session.status = success ? SkillStatus.done : SkillStatus.error);
      _syncForegroundService();

      final rawOutput = session.output.toString();
      final cleanOutput = SkillHistoryEntry.stripAnsi(rawOutput);
      SkillHistoryService.add(SkillHistoryEntry(
        skillId: skill.id,
        skillName: skill.name,
        arguments: arguments,
        startedAt: startTime,
        finishedAt: DateTime.now(),
        success: success,
        output: cleanOutput,
      ));
      NotificationService.show(
        title: '${skill.name} ${success ? 'terminé' : '— Erreur'}',
        body: success ? 'Tap pour voir le résultat' : 'Code de sortie: $exitCode',
      );
    } catch (e) {
      terminal.write('\r\n[Erreur: $e]\r\n');
      session.errorMessage = e.toString();
      setState(() => session.status = SkillStatus.error);
      _syncForegroundService();
      final rawOutput = session.output.toString();
      final cleanOutput = SkillHistoryEntry.stripAnsi(rawOutput);
      SkillHistoryService.add(SkillHistoryEntry(
        skillId: skill.id,
        skillName: skill.name,
        arguments: arguments,
        startedAt: startTime,
        finishedAt: DateTime.now(),
        success: false,
        output: cleanOutput.isNotEmpty ? cleanOutput : e.toString(),
      ));
      NotificationService.show(
        title: '${skill.name} — Erreur',
        body: e.toString(),
      );
    }
  }

  void _openTerminal() {
    final sessionId = 'terminal_${DateTime.now().millisecondsSinceEpoch}';

    final session = SkillSession(
      id: sessionId,
      skillId: '_terminal',
      skillName: 'Terminal Claude',
      startedAt: DateTime.now(),
    );

    final terminal = Terminal(maxLines: 10000);
    _terminals[sessionId] = terminal;

    setState(() {
      _sessions.add(session);
      _activeSessionId = sessionId;
    });

    _syncForegroundService(status: 'Terminal Claude');

    _connectTerminalSession(session, terminal);
  }

  void _syncForegroundService({String? status}) {
    final activeCount = _sessions.where((s) =>
        s.status == SkillStatus.running ||
        s.status == SkillStatus.connecting).length;
    ForegroundService.sync(activeCount, status: status);
  }

  Future<void> _connectTerminalSession(
      SkillSession session, Terminal terminal) async {
    terminal.write('Connexion SSH...\r\n');

    try {
      final socket = await SSHSocket.connect(
        _config.host,
        _config.port,
        timeout: const Duration(seconds: 10),
      );

      final client = SSHClient(
        socket,
        username: _config.username,
        onPasswordRequest: () => _config.password,
      );

      session.sshClient = client;
      setState(() => session.status = SkillStatus.running);

      terminal.write('Connecté.\r\n\r\n');

      final sshSession = await client.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );

      session.sshSession = sshSession;

      terminal.onOutput = (data) {
        sshSession.write(utf8.encode(data) as Uint8List);
      };

      terminal.onResize = (w, h, pw, ph) {
        sshSession.resizeTerminal(w, h, pw, ph);
      };

      sshSession.stdout.listen(
        (data) => terminal.write(utf8.decode(data, allowMalformed: true)),
        onDone: () {
          terminal.write('\r\n[Session terminée]\r\n');
          setState(() => session.status = SkillStatus.done);
          _syncForegroundService();
        },
      );

      await Future.delayed(const Duration(milliseconds: 500));
      sshSession.write(
          utf8.encode('export PATH="\$HOME/.local/bin:\$PATH" && claude --dangerously-skip-permissions\n') as Uint8List);
    } catch (e) {
      terminal.write('\r\n[Erreur: $e]\r\n');
      setState(() => session.status = SkillStatus.error);
      _syncForegroundService();
    }
  }

  void _closeSession(String id) {
    final session = _sessions.firstWhere((s) => s.id == id);
    session.dispose();
    setState(() {
      _sessions.removeWhere((s) => s.id == id);
      _terminals.remove(id);
      if (_activeSessionId == id) _activeSessionId = null;
    });
    _syncForegroundService();
  }

  Future<void> _showSkillDialog(Skill skill) async {
    if (!skill.hasArguments) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: Text(skill.name, style: const TextStyle(color: Colors.white)),
          content: Text(
            skill.description.isNotEmpty
                ? skill.description
                : 'Lancer ${skill.name} ?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler',
                  style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: skill.color),
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Lancer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm == true) _launchSkill(skill);
      return;
    }

    // Bottom sheet avec champ arguments (plus stable que AlertDialog avec TextField)
    final argsCtrl = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(skill.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            if (skill.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(skill.description,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: argsCtrl,
              autofocus: false,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.go,
              onSubmitted: (_) {
                FocusManager.instance.primaryFocus?.unfocus();
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (ctx.mounted) Navigator.pop(ctx, argsCtrl.text);
                });
              },
              decoration: InputDecoration(
                labelText: 'Arguments',
                hintText: 'Ex: jour, all, 6450 mars...',
                hintStyle: const TextStyle(color: Colors.white38),
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF0F3460),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (ctx.mounted) Navigator.pop(ctx);
                    });
                  },
                  child: const Text('Annuler',
                      style: TextStyle(color: Colors.white38)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: skill.color),
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (ctx.mounted) Navigator.pop(ctx, argsCtrl.text);
                    });
                  },
                  child: const Text('Lancer',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    argsCtrl.dispose();
    if (result != null) _launchSkill(skill, result);
  }

  Future<void> _showSkillOrHistory(Skill skill) async {
    final lastEntry = await SkillHistoryService.lastForSkill(skill.id);
    if (lastEntry != null && lastEntry.output != null && mounted) {
      _showOutputChoice(skill, lastEntry);
    } else {
      _showSkillDialog(skill);
    }
  }

  void _showOutputChoice(Skill skill, SkillHistoryEntry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(skill.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Dernier résultat : ${_formatDateTime(entry.finishedAt ?? entry.startedAt)} (${entry.durationStr})',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.article, size: 18),
                    label: const Text('Voir le résultat'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showOutputViewer(entry);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: skill.color,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.play_arrow,
                        size: 18, color: Colors.white),
                    label: const Text('Relancer',
                        style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showSkillDialog(skill);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showOutputViewer(SkillHistoryEntry entry) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OutputViewerScreen(entry: entry),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours}h';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildStatusBar(),
            if (_sessions.isNotEmpty) _buildTabBar(),
            Expanded(
              child: _activeSessionId != null
                  ? _buildTerminalView(_activeSessionId!)
                  : _buildDashboard(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.black87,
      child: Row(
        children: [
          _statusDot('VPN', _status?.vpnConnected),
          const SizedBox(width: 16),
          _statusDot('SSH', _status?.sshReachable),
          const Spacer(),
          if (_sessions.any((s) => s.status == SkillStatus.running))
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_sessions.where((s) => s.status == SkillStatus.running).length} en cours',
                  style: const TextStyle(
                      color: Colors.greenAccent, fontSize: 11),
                ),
              ),
            ),
          if (_isChecking || _isLoadingSkills)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white54),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              iconSize: 28,
              onPressed: () async {
                await _checkConnectivity();
                if (_status?.allGood == true) _discoverSkills();
              },
              tooltip: 'Recharger',
            ),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white70),
            iconSize: 28,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
            tooltip: 'Historique',
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            iconSize: 28,
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    config: _config,
                    onDiscoverSkills: _discoverSkills,
                  ),
                ),
              );
              _config = await SshConfig.load();
              _checkConnectivity();
            },
            tooltip: 'Paramètres',
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 40,
      color: const Color(0xFF16213E),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          GestureDetector(
            onTap: () => setState(() => _activeSessionId = null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: _activeSessionId == null
                    ? const Border(
                        bottom:
                            BorderSide(color: Colors.greenAccent, width: 2))
                    : null,
              ),
              child: Icon(Icons.dashboard, size: 18,
                  color: _activeSessionId == null
                      ? Colors.greenAccent
                      : Colors.white38),
            ),
          ),
          ..._sessions.map((s) {
            final isActive = _activeSessionId == s.id;
            final statusColor = switch (s.status) {
              SkillStatus.connecting => Colors.amber,
              SkillStatus.running => Colors.greenAccent,
              SkillStatus.done => Colors.white54,
              SkillStatus.error => Colors.redAccent,
            };
            return GestureDetector(
              onTap: () => setState(() => _activeSessionId = s.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: isActive
                      ? const Border(
                          bottom: BorderSide(
                              color: Colors.greenAccent, width: 2))
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                          color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.skillName.length > 12
                          ? '${s.skillName.substring(0, 12)}…'
                          : s.skillName,
                      style: TextStyle(
                          color: isActive ? Colors.white : Colors.white54,
                          fontSize: 12),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _closeSession(s.id),
                      child: const Icon(Icons.close,
                          size: 14, color: Colors.white24),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _statusDot(String label, bool? connected) {
    final color = connected == null
        ? Colors.grey
        : connected
            ? Colors.greenAccent
            : Colors.redAccent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          connected == true ? Icons.check_circle : Icons.circle_outlined,
          color: color, size: 14,
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildUsageWidget() {
    final u = _usage!;
    final age = DateTime.now().difference(u.fetchedAt);
    final ageStr =
        age.inMinutes < 1 ? 'à l\'instant' : 'il y a ${age.inMinutes}min';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.speed, color: Colors.white54, size: 16),
              const SizedBox(width: 6),
              const Text('Claude Max',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: u.activeSessions > 0
                      ? Colors.greenAccent.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  u.activeSessions > 0
                      ? '${u.activeSessions} actif'
                      : 'sleeping',
                  style: TextStyle(
                    color: u.activeSessions > 0
                        ? Colors.greenAccent
                        : Colors.white38,
                    fontSize: 10,
                  ),
                ),
              ),
              Text(ageStr,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 12),
          // Session actuelle
          _usageBar(
            'Session',
            u.sessionPercent,
            suffix: u.sessionReset.isNotEmpty ? 'reset ${u.sessionReset}' : null,
          ),
          const SizedBox(height: 8),
          // Hebdo
          _usageBar('Hebdo', u.weeklyPercent),
          if (u.extraEnabled) ...[
            const SizedBox(height: 8),
            _usageBar(
              'Extra',
              u.extraPercent,
              suffix: '${(u.extraUsed / 100).toStringAsFixed(0)}€/${(u.extraLimit / 100).toStringAsFixed(0)}€',
            ),
          ],
        ],
      ),
    );
  }

  Widget _usageBar(String label, int percent, {String? suffix}) {
    final remaining = 100 - percent;
    Color barColor;
    if (percent >= 80) {
      barColor = Colors.redAccent;
    } else if (percent >= 50) {
      barColor = Colors.amber;
    } else {
      barColor = Colors.greenAccent;
    }

    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 35,
          child: Text('$remaining%',
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: barColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 4),
          Text(suffix,
              style: const TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ],
    );
  }

  Widget _usageStat(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.greenAccent, size: 18),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(0)}K';
    return '$tokens';
  }

  String _formatNumber(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Widget _buildDashboard() {
    if (_skills.isEmpty && !_isLoadingSkills) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            const Text('Aucune skill trouvée',
                style: TextStyle(color: Colors.white38, fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black),
              icon: const Icon(Icons.refresh),
              label: const Text('Rechercher'),
              onPressed:
                  _status?.allGood == true ? _discoverSkills : null,
            ),
            const SizedBox(height: 48),
            _buildTerminalCard(),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      color: Colors.greenAccent,
      backgroundColor: const Color(0xFF16213E),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_usage != null) ...[
                  _buildUsageWidget(),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    const Text('Skills',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('${_skills.length} skills',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 12),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
                ..._skills.map((s) => _buildSkillCard(s)),
                _buildTerminalCard(),
              ],
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
        ],
      ),
    );
  }

  Widget _buildSkillCard(Skill skill) {
    // Trouver les sessions liées à cette skill
    final relatedSessions = _sessions.where((s) => s.skillId == skill.id).toList();
    final runningSession = relatedSessions
        .where((s) => s.status == SkillStatus.running)
        .toList();
    final doneSession = relatedSessions
        .where((s) => s.status == SkillStatus.done)
        .toList();
    final errorSession = relatedSessions
        .where((s) => s.status == SkillStatus.error)
        .toList();

    final isRunning = runningSession.isNotEmpty;
    final isDone = doneSession.isNotEmpty;
    final isError = errorSession.isNotEmpty;
    final hasSession = relatedSessions.isNotEmpty;

    // Statut à afficher
    String? statusText;
    Color? statusColor;
    if (isRunning) {
      statusText = 'En cours';
      statusColor = Colors.greenAccent;
    } else if (isDone) {
      statusText = 'Terminé';
      statusColor = Colors.white54;
    } else if (isError) {
      statusText = 'Erreur';
      statusColor = Colors.redAccent;
    }

    return GestureDetector(
      onTap: () {
        if (hasSession) {
          // Afficher le terminal de la session la plus récente
          final session = relatedSessions.last;
          setState(() => _activeSessionId = session.id);
        } else {
          // Vérifier s'il y a un résultat dans l'historique
          _showSkillOrHistory(skill);
        }
      },
      onLongPress: () => _showSkillDialog(skill),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              skill.color.withValues(alpha: 0.8),
              skill.color.withValues(alpha: 0.4),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: isRunning
              ? Border.all(color: Colors.greenAccent, width: 2)
              : isDone
                  ? Border.all(color: Colors.white24, width: 1)
                  : isError
                      ? Border.all(color: Colors.redAccent, width: 1)
                      : null,
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(skill.icon, color: Colors.white, size: 28),
                const Spacer(),
                if (isRunning)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.greenAccent),
                  )
                else if (statusText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor!.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(statusText,
                        style: TextStyle(
                            color: statusColor, fontSize: 9)),
                  )
                else if (skill.hasArguments)
                  const Icon(Icons.tune, color: Colors.white38, size: 16),
              ],
            ),
            const Spacer(),
            Text(skill.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            if (hasSession)
              Text(
                isRunning
                    ? 'Tap pour voir le détail'
                    : 'Tap: détail · Long: relancer',
                style: TextStyle(color: statusColor, fontSize: 10),
              )
            else
              Text(skill.description,
                  style:
                      const TextStyle(color: Colors.white60, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminalCard() {
    return GestureDetector(
      onTap: _openTerminal,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.15),
              Colors.white.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.all(14),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('>_',
                style: TextStyle(
                    fontSize: 26,
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace')),
            Spacer(),
            Text('Terminal Claude',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 2),
            Text('Session interactive',
                style: TextStyle(color: Colors.white60, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminalView(String sessionId) {
    final terminal = _terminals[sessionId];
    final session = _sessions.firstWhere((s) => s.id == sessionId);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF0F3460),
          child: Row(
            children: [
              Icon(
                session.skillId == '_terminal'
                    ? Icons.terminal
                    : Icons.play_arrow,
                color: Colors.greenAccent, size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(session.skillName,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 14),
                    overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: switch (session.status) {
                    SkillStatus.connecting =>
                      Colors.amber.withValues(alpha: 0.2),
                    SkillStatus.running =>
                      Colors.greenAccent.withValues(alpha: 0.2),
                    SkillStatus.done =>
                      Colors.white.withValues(alpha: 0.1),
                    SkillStatus.error =>
                      Colors.redAccent.withValues(alpha: 0.2),
                  },
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  switch (session.status) {
                    SkillStatus.connecting => 'Connexion...',
                    SkillStatus.running => 'En cours',
                    SkillStatus.done => 'Terminé',
                    SkillStatus.error => 'Erreur',
                  },
                  style: TextStyle(
                    color: switch (session.status) {
                      SkillStatus.connecting => Colors.amber,
                      SkillStatus.running => Colors.greenAccent,
                      SkillStatus.done => Colors.white54,
                      SkillStatus.error => Colors.redAccent,
                    },
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Kill button
              if (session.status == SkillStatus.running ||
                  session.status == SkillStatus.connecting)
                GestureDetector(
                  onTap: () => _killSession(session.id),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.stop,
                        color: Colors.redAccent, size: 18),
                  ),
                ),
              const SizedBox(width: 6),
              // Close button
              GestureDetector(
                onTap: () => _closeSession(session.id),
                child: const Icon(Icons.close,
                    color: Colors.white38, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: terminal != null
              ? TerminalView(
                  terminal,
                  textStyle: const TerminalStyle(
                      fontSize: 12, fontFamily: 'monospace'),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  void _killSession(String id) async {
    final session = _sessions.firstWhere((s) => s.id == id);
    final terminal = _terminals[id];

    terminal?.write('\r\n[KILL en cours...]\r\n');

    // 1. Fermer la connexion SSH → envoie SIGHUP au processus distant
    session.dispose();

    // 2. Attendre un peu puis vérifier si le processus est mort
    await Future.delayed(const Duration(seconds: 2));

    // 3. Si le processus survit au SIGHUP, forcer le kill via une nouvelle connexion
    try {
      final socket = await SSHSocket.connect(
        _config.host,
        _config.port,
        timeout: const Duration(seconds: 5),
      );
      final killClient = SSHClient(
        socket,
        username: _config.username,
        onPasswordRequest: () => _config.password,
      );
      // Chercher et tuer les processus claude orphelins de cette session
      // Le SIGHUP devrait avoir tué le shell parent, mais claude peut survivre
      final result = await killClient.run(
        'pgrep -f "claude.*--dangerously-skip-permissions.*-p" >/dev/null 2>&1 && '
        'pkill -KILL -P \$(pgrep -f "cat.*claude/commands.*\\.md") 2>/dev/null; '
        'pkill -KILL -f "cat.*claude/commands.*\\.md" 2>/dev/null',
      );
      killClient.close();
      terminal?.write('[Processus tué]\r\n');
    } catch (e) {
      // Le SIGHUP a suffi, pas besoin du kill forcé
      terminal?.write('[Session fermée]\r\n');
    }

    setState(() => session.status = SkillStatus.error);
    _syncForegroundService();
  }
}

class OutputViewerScreen extends StatelessWidget {
  final SkillHistoryEntry entry;

  const OutputViewerScreen({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        title: Text(entry.skillName),
        backgroundColor: const Color(0xFF16213E),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: entry.success
                  ? Colors.greenAccent.withValues(alpha: 0.2)
                  : Colors.redAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  entry.success ? Icons.check_circle : Icons.error,
                  color: entry.success ? Colors.greenAccent : Colors.redAccent,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  entry.durationStr,
                  style: TextStyle(
                    color:
                        entry.success ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Info bar
          if (entry.arguments != null && entry.arguments!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF16213E),
              child: Text(
                'Arguments : ${entry.arguments}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          // Output
          Expanded(
            child: entry.output != null && entry.output!.isNotEmpty
                ? Scrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        entry.output!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    ),
                  )
                : const Center(
                    child: Text('Aucun output enregistré',
                        style: TextStyle(color: Colors.white38)),
                  ),
          ),
        ],
      ),
    );
  }
}
