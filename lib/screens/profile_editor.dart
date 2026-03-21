import 'package:flutter/material.dart';

import '../models/ssh_profile.dart';

class ProfileEditor extends StatefulWidget {
  final SshProfile? profile;

  const ProfileEditor({super.key, this.profile});

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _cmdCtrl;
  late final TextEditingController _dirCtrl;
  late final TextEditingController _extraArgsCtrl;
  late bool _skipPermissions;
  String? _claudeModel;
  final _formKey = GlobalKey<FormState>();

  static const _models = [
    null,
    'opus',
    'sonnet',
    'haiku',
  ];

  static const _modelLabels = [
    'Par défaut',
    'Opus',
    'Sonnet',
    'Haiku',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _hostCtrl = TextEditingController(text: p?.host ?? '192.168.0.157');
    _portCtrl = TextEditingController(text: '${p?.port ?? 22}');
    _userCtrl = TextEditingController(text: p?.username ?? 'zonief');
    _passCtrl = TextEditingController(text: p?.password ?? '');
    _cmdCtrl =
        TextEditingController(text: p?.startupCommand ?? 'claude-session');
    _dirCtrl = TextEditingController(text: p?.workingDirectory ?? '');
    _extraArgsCtrl = TextEditingController(text: p?.claudeExtraArgs ?? '');
    _skipPermissions = p?.skipPermissions ?? true;
    _claudeModel = p?.claudeModel;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _cmdCtrl.dispose();
    _dirCtrl.dispose();
    _extraArgsCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final profile = SshProfile(
      id: widget.profile?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 22,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
      startupCommand:
          _cmdCtrl.text.trim().isEmpty ? null : _cmdCtrl.text.trim(),
      skipPermissions: _skipPermissions,
      claudeModel: _claudeModel,
      workingDirectory:
          _dirCtrl.text.trim().isEmpty ? null : _dirCtrl.text.trim(),
      claudeExtraArgs:
          _extraArgsCtrl.text.trim().isEmpty ? null : _extraArgsCtrl.text.trim(),
    );

    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.profile != null;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: Text(isEdit ? 'Modifier le profil' : 'Nouveau profil'),
        backgroundColor: const Color(0xFF16213E),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Enregistrer',
                style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- Connexion SSH ---
            _sectionHeader('Connexion SSH'),
            const SizedBox(height: 8),
            _field(_nameCtrl, 'Nom du profil', Icons.label,
                validator: _required),
            const SizedBox(height: 12),
            _field(_hostCtrl, 'Hôte', Icons.computer, validator: _required),
            const SizedBox(height: 12),
            _field(_portCtrl, 'Port', Icons.numbers,
                keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            _field(_userCtrl, 'Utilisateur', Icons.person,
                validator: _required),
            const SizedBox(height: 12),
            _field(_passCtrl, 'Mot de passe', Icons.lock, obscure: true),

            const SizedBox(height: 24),

            // --- Claude Code ---
            _sectionHeader('Claude Code'),
            const SizedBox(height: 8),
            _field(_cmdCtrl, 'Commande de lancement', Icons.terminal),
            const SizedBox(height: 4),
            const Text(
              'Ex: claude-session (le nom est ajouté automatiquement)',
              style: TextStyle(color: Colors.white24, fontSize: 11),
            ),
            const SizedBox(height: 12),
            _field(_dirCtrl, 'Répertoire de travail', Icons.folder),
            const SizedBox(height: 4),
            const Text(
              'Ex: ~/IdeaProjects/pistemploi',
              style: TextStyle(color: Colors.white24, fontSize: 11),
            ),
            const SizedBox(height: 16),

            // Skip permissions toggle
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F3460),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SwitchListTile(
                title: const Text('Skip permissions',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  '--dangerously-skip-permissions',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                value: _skipPermissions,
                activeColor: Colors.greenAccent,
                onChanged: (v) => setState(() => _skipPermissions = v),
              ),
            ),
            const SizedBox(height: 12),

            // Model selector
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F3460),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonFormField<String?>(
                value: _claudeModel,
                dropdownColor: const Color(0xFF0F3460),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Modèle Claude',
                  labelStyle: TextStyle(color: Colors.white54),
                  prefixIcon:
                      Icon(Icons.psychology, color: Colors.white38),
                  border: InputBorder.none,
                ),
                items: List.generate(
                  _models.length,
                  (i) => DropdownMenuItem(
                    value: _models[i],
                    child: Text(_modelLabels[i]),
                  ),
                ),
                onChanged: (v) => setState(() => _claudeModel = v),
              ),
            ),
            const SizedBox(height: 12),

            _field(_extraArgsCtrl, 'Arguments supplémentaires',
                Icons.code),
            const SizedBox(height: 4),
            const Text(
              'Ex: --verbose --allowedTools "Bash(npm:*)"',
              style: TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Requis' : null;

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
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
