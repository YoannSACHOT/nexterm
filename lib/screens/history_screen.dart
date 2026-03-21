import 'package:flutter/material.dart';

import '../models/skill_history.dart';
import 'home_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<SkillHistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await SkillHistoryService.load();
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return "Aujourd'hui";
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day) {
      return 'Hier';
    }
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        title: const Text('Historique'),
        backgroundColor: const Color(0xFF16213E),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: Colors.greenAccent))
          : _entries.isEmpty
              ? const Center(
                  child: Text('Aucune exécution',
                      style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  itemCount: _entries.length,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (ctx, i) {
                    final e = _entries[i];
                    // Séparateur de date
                    final showDate = i == 0 ||
                        _formatDate(e.startedAt) !=
                            _formatDate(_entries[i - 1].startedAt);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showDate)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              _formatDate(e.startedAt),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        GestureDetector(
                          onTap: e.output != null && e.output!.isNotEmpty
                              ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          OutputViewerScreen(entry: e),
                                    ),
                                  )
                              : null,
                          child: Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 3),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF16213E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: e.success
                                  ? Colors.greenAccent.withValues(alpha: 0.15)
                                  : Colors.redAccent.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                e.success
                                    ? Icons.check_circle
                                    : Icons.error,
                                color: e.success
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.skillName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (e.arguments != null &&
                                        e.arguments!.isNotEmpty)
                                      Text(
                                        e.arguments!,
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 11),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${_formatTime(e.startedAt)} → ${e.finishedAt != null ? _formatTime(e.finishedAt!) : '...'}',
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    e.durationStr,
                                    style: TextStyle(
                                      color: e.success
                                          ? Colors.greenAccent
                                          : Colors.redAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              if (e.output != null && e.output!.isNotEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(Icons.chevron_right,
                                      color: Colors.white24, size: 20),
                                ),
                            ],
                          ),
                        ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}
