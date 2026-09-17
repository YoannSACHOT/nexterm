enum CodingAgent {
  codex('Codex', 'codex'),
  claude('Claude Code', 'claude');

  const CodingAgent(this.label, this.executable);
  final String label;
  final String executable;
}

class AgentLauncher {
  const AgentLauncher(this.agent, {this.autonomous = false});

  final CodingAgent agent;
  final bool autonomous;

  static const cards = [
    AgentLauncher(CodingAgent.codex),
    AgentLauncher(CodingAgent.claude),
    AgentLauncher(CodingAgent.codex, autonomous: true),
    AgentLauncher(CodingAgent.claude, autonomous: true),
  ];

  static const prompt =
      'Cherche et résous la prochaine issue activable en autonomie. '
      'Respecte les instructions du projet et le protocole de prise des issues. '
      'Vérifie le résultat réel, sauvegarde et pousse ton travail avant de terminer. '
      'Si une suite doit continuer, confie-la à un exécutant persistant vérifié. '
      'Ne touche pas au travail des autres sessions. '
      'À la fin, le lanceur consultera le hook de fermeture et fermera cette '
      'session uniquement quand il recevra son signal VERT. '
      'Ne contourne pas le hook et signale tout blocage.';

  String get id => '${autonomous ? 'session' : 'terminal'}_${agent.name}';
  String get title => autonomous ? 'Session ${agent.label}' : agent.label;
  String get description => autonomous
      ? 'Prochaine issue · fermeture au feu vert'
      : 'Terminal interactif';

  static String shellQuote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";

  String buildCommand({String cycleLockDirectory = '/tmp'}) {
    const setup =
        r'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"; '
        r'cd "$HOME" || exit 72; ';
    final cli = agent == CodingAgent.claude
        ? 'claude --dangerously-skip-permissions'
        : 'codex';
    if (!autonomous) return '${setup}exec $cli';

    final regularLock = shellQuote('$cycleLockDirectory/ops-issues.lock');
    final ilotiaLock = shellQuote('$cycleLockDirectory/ops-issues-ilotia.lock');
    final run = agent == CodingAgent.claude
        ? '$cli -p ${shellQuote(prompt)}'
        : '$cli exec --skip-git-repo-check ${shellQuote(prompt)}';
    // --check is essential: Stop may silently acknowledge RED and exit 0.
    return setup +
        r'''hook="$HOME/.claude/hooks/session-closable.sh"
if [ ! -x "$hook" ]; then
  printf '%s\n' 'Hook de fermeture absent ou non exécutable. Session conservée.'
  exit 78
fi
''' +
        '$run\n' +
        r'''
agent_status=$?
[ "$agent_status" -eq 0 ] || exit "$agent_status"
previous_verdict=''
while :; do
  verdict=$("$hook" --check 2>&1)
  hook_status=$?
  if [ "$hook_status" -eq 0 ]; then
    case "$verdict" in
      'VERT : '*)
        if [ ! -e /tmp/ops-issues.lock ] && [ ! -L /tmp/ops-issues.lock ] &&
           [ ! -e /tmp/ops-issues-ilotia.lock ] && [ ! -L /tmp/ops-issues-ilotia.lock ]; then
          printf '%s\n' "$verdict"
          exit 0
        fi
        verdict='Un cycle ops est encore actif. Attente avant fermeture.'
        ;;
      *) printf '%s\n' 'Verdict de fermeture indécidable. Session conservée.' "$verdict"; exit 78 ;;
    esac
  elif [ "$hook_status" -ne 1 ]; then
    printf '%s\n' 'Erreur du hook de fermeture. Session conservée.' "$verdict"
    exit 78
  else
    case "$verdict" in
      'ROUGE : '*) ;;
      *) printf '%s\n' 'Verdict de fermeture indécidable. Session conservée.' "$verdict"; exit 78 ;;
    esac
  fi
  if [ "$verdict" != "$previous_verdict" ]; then
    printf '%s\n' "$verdict" 'En attente du feu vert du hook (contrôle toutes les 15 secondes).'
    previous_verdict=$verdict
  fi
  sleep 15
done'''
            .replaceAll('/tmp/ops-issues.lock', regularLock)
            .replaceAll('/tmp/ops-issues-ilotia.lock', ilotiaLock);
  }

  bool shouldClose(int? exitCode) => autonomous && exitCode == 0;
}
