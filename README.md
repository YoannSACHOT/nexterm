# Nexterm

> Client terminal mobile pour [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — lancez vos skills, ouvrez un terminal interactif et surveillez votre usage, le tout depuis votre smartphone.

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.11+-blue?logo=flutter" />
  <img src="https://img.shields.io/badge/Dart-3.11+-blue?logo=dart" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Desktop-green" />
  <img src="https://img.shields.io/badge/License-MIT-yellow" />
</p>

## Fonctionnalités

- **Découverte automatique des skills** — scanne vos `commands/*.md` et `skills/*/SKILL.md` sur le serveur distant via SSH
- **Exécution de skills** — lancez n'importe quelle skill Claude Code avec ou sans arguments, avec capture complète de la sortie
- **Terminal interactif** — session shell SSH complète avec émulateur xterm intégré (PTY, redimensionnement auto)
- **Monitoring Claude Max** — usage session (5h), hebdomadaire, Sonnet, crédits extra, sessions actives — rafraîchi toutes les 2 min
- **Historique d'exécution** — les 50 dernières exécutions avec statut, durée et sortie consultable
- **Profils SSH multiples** — sauvegardez plusieurs configurations serveur
- **Indicateurs de connectivité** — statut VPN et SSH en temps réel
- **Notifications** — alerte locale quand une skill se termine
- **Sessions SSH persistantes en arrière-plan** — un foreground service Android (notification permanente + WAKE_LOCK) maintient les sessions SSH actives même quand vous changez d'application, verrouillez l'écran ou lancez un autre app

## Prérequis

| Composant | Version |
|-----------|---------|
| Flutter SDK | 3.11+ |
| Dart | 3.11+ |
| Serveur distant | Linux avec [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installé |
| Accès SSH | Par mot de passe (port 22 par défaut) |

Le serveur distant doit avoir :
- Claude Code installé et fonctionnel
- Le fichier `~/.claude/usage-cache.json` (généré automatiquement par Claude Code)
- Des skills définies dans `~/.claude/commands/` ou `~/IdeaProjects/*/` (optionnel)

## Installation

### 1. Cloner le repo

```bash
git clone https://github.com/YoannSACHOT/nexterm.git
cd nexterm
```

### 2. Configurer la connexion SSH

Copiez le fichier d'exemple et renseignez vos identifiants :

```bash
cp config.example.json config.local.json
```

Éditez `config.local.json` avec vos paramètres :

```json
{
  "host": "192.168.1.100",
  "port": 22,
  "username": "ubuntu",
  "password": "votre-mot-de-passe",
  "excludePatterns": ["bmad"]
}
```

> **Ce fichier est ignoré par git** — vos identifiants ne seront jamais commités.

Au premier lancement, l'app charge automatiquement cette config. Vous pouvez ensuite la modifier depuis l'écran Paramètres.

### 3. Installer les dépendances

```bash
flutter pub get
```

### 4. Lancer sur un appareil

```bash
# Android (appareil connecté en USB)
flutter run

# iOS
flutter run -d ios

# Linux desktop
flutter run -d linux

# Web (limité — pas de SSH natif)
flutter run -d chrome
```

### 5. Build release Android

```bash
flutter build apk --release
# APK dans build/app/outputs/flutter-apk/app-release.apk
```

## Configuration

Au premier lancement, allez dans **Paramètres** (icône engrenage) et renseignez :

| Champ | Description | Exemple |
|-------|-------------|---------|
| **Host** | IP ou hostname du serveur | `192.168.1.100` |
| **Port** | Port SSH | `22` |
| **Username** | Utilisateur SSH | `ubuntu` |
| **Password** | Mot de passe SSH | `•••••` |
| **Exclude patterns** | Skills à masquer (séparées par virgule) | `bmad,deprecated` |

La configuration est stockée localement sur l'appareil (SharedPreferences).

## Utilisation

### Dashboard

L'écran principal affiche :
- **Barre de statut** — indicateurs VPN (●) et SSH (●) en vert/rouge
- **Grille de skills** — toutes les skills découvertes, avec icône et couleur par projet
- **Terminal Claude** — carte spéciale pour ouvrir un terminal interactif

### Lancer une skill

1. Tapez sur une carte skill
2. Si la skill accepte des arguments, un champ de saisie apparaît
3. Confirmez — la skill s'exécute sur le serveur distant
4. La sortie s'affiche en temps réel dans un terminal intégré
5. Une notification apparaît quand c'est terminé

### Terminal interactif

1. Tapez sur **Terminal Claude**
2. Une session SSH interactive s'ouvre avec Claude Code pré-lancé
3. Tapez vos commandes comme dans un vrai terminal
4. Le terminal supporte le redimensionnement automatique

### Monitoring usage

Le panneau usage (accessible depuis le dashboard) affiche :
- **Session (5h)** — pourcentage d'utilisation + temps avant reset
- **Hebdo (7j)** — pourcentage d'utilisation hebdomadaire
- **Sonnet (7j)** — utilisation du modèle Sonnet
- **Extra** — crédits supplémentaires consommés
- **Sessions actives** — nombre de processus Claude en cours

### Historique

Tapez l'icône historique (🕐) pour voir les exécutions passées, groupées par jour, avec statut succès/erreur, durée et sortie complète.

## Architecture

```
lib/
├── main.dart                     # Point d'entrée, thème dark
├── screens/
│   ├── home_screen.dart          # Dashboard principal
│   ├── history_screen.dart       # Historique d'exécution
│   ├── settings_screen.dart      # Configuration SSH
│   └── profile_editor.dart       # Éditeur de profils SSH
├── models/
│   ├── ssh_config.dart           # Configuration SSH (singleton)
│   ├── skill.dart                # Métadonnées d'une skill
│   ├── ssh_profile.dart          # Profil SSH sauvegardé
│   ├── skill_session.dart        # Session d'exécution en cours
│   ├── skill_history.dart        # Entrée d'historique persistée
│   └── terminal_tab.dart         # Onglet terminal
├── services/
│   ├── connectivity_service.dart # Vérification VPN + SSH
│   ├── skill_discovery.dart      # Scan distant des skills
│   ├── ssh_service.dart          # Connexion SSH shell
│   ├── usage_service.dart        # Lecture usage Claude Max
│   ├── notification_service.dart # Notifications locales
│   ├── foreground_service.dart   # Bridge vers le foreground service Android
│   └── profile_service.dart      # Persistance profils

android/app/src/main/kotlin/com/jixter/claude_terminal/
├── MainActivity.kt               # Activité Flutter + MethodChannel foreground service
└── SshKeepAliveService.kt        # Foreground service (notification permanente + WAKE_LOCK)
└── widgets/
    └── status_bar.dart           # Widget indicateurs VPN/SSH
```

## Dépendances

| Package | Usage |
|---------|-------|
| [dartssh2](https://pub.dev/packages/dartssh2) | Client SSH (connexion, shell, exécution) |
| [xterm](https://pub.dev/packages/xterm) | Émulateur de terminal (widget Flutter) |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | Persistance locale (config, cache, historique) |
| [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) | Notifications Android/iOS |

## Sessions SSH en arrière-plan (Android)

Par défaut, Android tue les processus en arrière-plan pour libérer la mémoire — ce qui ferme aussi les sockets SSH. Nexterm contourne ça avec un **foreground service** :

- Activé automatiquement dès qu'une session SSH est ouverte (skill ou terminal)
- Affiche une notification permanente `Nexterm — N session(s) active(s)` qui empêche l'OS de killer le processus
- Type `dataSync` (obligatoire Android 14+), avec `PARTIAL_WAKE_LOCK` pour 8h max
- Stoppé automatiquement quand toutes les sessions sont fermées ou terminées

Permissions requises : `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `WAKE_LOCK`, `POST_NOTIFICATIONS` (demandée au runtime au premier lancement).

## Licence

MIT — voir [LICENSE](LICENSE).

## Auteur

Développé par **JIXTER** (Yoann).
