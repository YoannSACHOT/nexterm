import 'package:flutter/material.dart';

import '../models/ssh_config.dart';

class SettingsScreen extends StatefulWidget {
  final SshConfig config;
  final VoidCallback? onDiscoverSkills;

  const SettingsScreen({
    super.key,
    required this.config,
    this.onDiscoverSkills,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _excludeCtrl;

  @override
  void initState() {
    super.initState();
    _hostCtrl = TextEditingController(text: widget.config.host);
    _portCtrl = TextEditingController(text: '${widget.config.port}');
    _userCtrl = TextEditingController(text: widget.config.username);
    _passCtrl = TextEditingController(text: widget.config.password);
    _excludeCtrl = TextEditingController(
        text: widget.config.excludePatterns.join(', '));
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _excludeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    widget.config.host = _hostCtrl.text.trim();
    widget.config.port = int.tryParse(_portCtrl.text.trim()) ?? 22;
    widget.config.username = _userCtrl.text.trim();
    widget.config.password = _passCtrl.text;
    widget.config.excludePatterns = _excludeCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    await widget.config.save();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('Paramètres'),
        backgroundColor: const Color(0xFF16213E),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Enregistrer',
                style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('CONNEXION SSH',
              style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
          const SizedBox(height: 12),
          _field(_hostCtrl, 'Hôte', Icons.computer),
          const SizedBox(height: 12),
          _field(_portCtrl, 'Port', Icons.numbers,
              keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _field(_userCtrl, 'Utilisateur', Icons.person),
          const SizedBox(height: 12),
          _field(_passCtrl, 'Mot de passe', Icons.lock, obscure: true),
          const SizedBox(height: 32),
          const Text('FILTRES',
              style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
          const SizedBox(height: 12),
          _field(_excludeCtrl, 'Exclure (séparés par virgule)', Icons.filter_alt),
          const SizedBox(height: 4),
          const Text(
            'Ex: bmad, test, deprecated',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
          const SizedBox(height: 32),
          const Text('SKILLS',
              style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F3460),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.search, size: 24),
              label: const Text('Rechercher les skills sur la machine',
                  style: TextStyle(fontSize: 15)),
              onPressed: () {
                widget.onDiscoverSkills?.call();
                Navigator.pop(context);
              },
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scanne ~/.claude/commands/ sur la machine distante',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {bool obscure = false, TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF0F3460),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.greenAccent),
        ),
      ),
    );
  }
}
