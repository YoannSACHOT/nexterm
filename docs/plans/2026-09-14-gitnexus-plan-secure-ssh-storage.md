# GitNexus Engineering Plan

> Task: Résoudre ops#2175 en imposant TOFU pour toutes les connexions SSH, en migrant les secrets vers le coffre natif et en durcissant le build Android.
> Evidence verified at commit 102375b68173a55d5e018e8427a207b4d111cbf2; GitNexus index refreshed this session with `analyze --index-only --pdg` using CLI 1.6.10 and runner identity schema 4.
> Evidence provenance schema 2; global dirty digest 0a9c85780067d9afcd0764f307b60891e3cee927ee11eaeb5ec7826d10fd82cd; cited-path manifest 22 sorted entries; exact generated plan path excluded.

## 1. Objective

Empêcher toute acceptation silencieuse d’une clé d’hôte SSH, confirmer et mémoriser de façon sûre la première empreinte, refuser les changements ultérieurs, sortir mots de passe et données d’historique sensibles de `SharedPreferences`, puis rendre le build Android release non signable avec la clé debug, minifié et obligatoirement obfusqué par le chemin de build documenté.

## 2. Current Behaviour

- [verified] Les sept créations `SSHClient` de `home_screen.dart`, `skill_discovery.dart`, `ssh_service.dart` et `usage_service.dart` omettent `onVerifyHostKey`; dartssh2 accepte alors la clé reçue (`lib/screens/home_screen.dart:151-161`, `297-312`, `1283-1293`; `lib/services/skill_discovery.dart:14-24`; `lib/services/ssh_service.dart:31-42`, `103-114`; `lib/services/usage_service.dart:38-50`).
- [verified] `SshConfig.toJson/save` et `SshProfile.toJson/ProfileService.saveProfiles` écrivent les mots de passe dans `SharedPreferences` (`lib/models/ssh_config.dart:21-59`; `lib/models/ssh_profile.dart:76-107`; `lib/services/profile_service.dart:10-39`).
- [verified] Les arguments et sorties terminal sont écrits en clair dans une liste de 50 entrées, puis réaffichés (`lib/models/skill_history.dart:49-107`; `lib/screens/home_screen.dart:229-259`).
- [verified] `config.local.json` peut être embarqué comme asset et le README conseille d’y inscrire le mot de passe (`pubspec.yaml:57-65`; `README.md:47-69`).
- [verified] Android autorise tout HTTP clair et la release emploie explicitement la signature debug sans configuration R8 (`android/app/src/main/AndroidManifest.xml:8-12`; `android/app/build.gradle.kts:34-39`).
- [verified] La seule suite actuelle échoue avant correction sur un défaut de layout sans lien avec ops#2175 (`test/widget_test.dart:6-10`; commande `flutter test`, 1 test rouge, 9 exceptions de layout).

## 3. Relevant Architecture

- [verified] `HomeScreen` charge le singleton `SshConfig`, déclenche automatiquement découverte et usage, et possède trois des sept connexions SSH ainsi que le `BuildContext` nécessaire au dialogue TOFU (`lib/screens/home_screen.dart:28-68`, `81-123`, `126-265`, `297-330`, `1270-1306`).
- [verified] Les quatre autres connexions sont réparties dans des services statiques ou un service de profils, sans abstraction commune de création du client.
- [verified] `SharedPreferences` reste approprié pour les métadonnées non sensibles et caches; le nouveau coffre devra être injectable afin de tester migrations et décisions TOFU sans canal plateforme.
- [inferred] Une fabrique SSH unique est la garde la plus robuste contre la réapparition d’un constructeur non vérifié, à condition qu’un test interdise les constructions ailleurs.

## 4. GitNexus Findings

- [graph] `query(repo:nexterm, search_query:"SSHClient host key verification...")` identifie `SshService.connect`, `SshConfig`, `ProfileService`, `SkillDiscovery` et les propriétés de mot de passe comme noyau du changement.
- [graph] `impact(SshConfig.load, upstream, maxDepth:2)` trouve deux dépendants directs, `_HomeScreenState._init` et `_buildStatusBar`, risque LOW.
- [graph] `impact(ProfileService.saveProfiles, upstream, maxDepth:2)` trouve trois dépendants directs: `addProfile`, `updateProfile`, `deleteProfile`, risque LOW.
- [graph] `impact(SkillHistoryService.add, upstream, maxDepth:2)` trouve `_launchSkill` comme dépendant direct mais qualifie le résultat de lower-bound à cause de deux appels à résolution incomplète; la recherche source confirme exactement les deux appels dans `_launchSkill`.
- [graph] `impact(_launchSkill, upstream, maxDepth:2)` trouve `_showSkillDialog` comme seul dépendant direct, risque LOW.
- [graph] `impact(SshService.connect, upstream, maxDepth:2)` ne résout aucun appelant; la recherche source confirme que ce service de profils n’est actuellement pas appelé par l’UI.

## 5. Statement-Level PDG Findings

- [graph] Après indexation `--pdg`, `pdg_query` sur `SshConfig`, `ProfileService` et `_launchSkill` ne retourne aucune arête de contrôle ou de données exploitable pour ce code Dart.
- [graph] `explain` ne retourne aucun chemin de taint et rappelle que les propriétés, closures et flux implicites ne sont pas modélisés; cette absence ne constitue donc pas une preuve de sûreté.
- [verified] L’ordre de migration doit être coffre écrit avec succès, puis suppression de la copie en clair. Inverser cet ordre risquerait une perte de secret lors d’un échec plateforme.
- [verified] L’ordre TOFU doit être lecture de la confiance, confirmation seulement si elle est absente, écriture après acceptation, puis comparaison stricte sans nouvelle confirmation lorsque l’hôte change.

## 6. Proposed Changes

- `lib/services/secure_storage_service.dart`: ajouter `SecretStore` injectable et l’implémentation `FlutterSecureStorage` configurée pour Android Keystore et Apple Keychain.
- `lib/models/ssh_config.dart`, `lib/models/ssh_profile.dart`, `lib/services/profile_service.dart`: sérialiser uniquement les métadonnées, migrer les mots de passe legacy vers des clés de coffre séparées, nettoyer `SharedPreferences` seulement après écriture sûre et supprimer le bootstrap secret embarqué.
- `lib/models/skill_history.dart`, `lib/screens/home_screen.dart`: conserver au plus 50 métadonnées d’exécution, supprimer arguments et sortie brute de toute nouvelle persistance et réécrire les anciennes entrées nettoyées au démarrage.
- `lib/services/host_key_trust_service.dart`: modéliser l’empreinte et la décision TOFU, sérialiser la confiance dans le coffre par `host:port`, mutualiser les confirmations concurrentes et refuser strictement toute empreinte différente.
- `lib/services/ssh_client_factory.dart`, `lib/services/skill_discovery.dart`, `lib/services/ssh_service.dart`, `lib/services/usage_service.dart`, `lib/screens/home_screen.dart`: centraliser `SSHClient`, rendre la confirmation obligatoire et afficher un dialogue non dismissible contenant type et empreinte lors de la première connexion.
- `pubspec.yaml`, `pubspec.lock`, `.gitignore`: ajouter et verrouiller `flutter_secure_storage`, ne plus embarquer `config.local.json`, versionner le lockfile applicatif.
- `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `tool/build_android_release.sh`, `README.md`: retirer HTTP clair et signature debug, exiger des credentials release, activer R8/shrinkResources et fournir le seul chemin documenté avec `--obfuscate --split-debug-info`.

## 7. Implementation Sequence

1. Ajouter les témoins de sécurité statiques et comportementaux, puis les exécuter sur le code ancien pour observer l’échec attendu.
2. Ajouter le coffre injectable et migrer configuration, profils et historique avec tests de succès, nettoyage et échec sans perte; commit atomique.
3. Ajouter TOFU et la fabrique SSH, câbler les sept connexions et le dialogue UI, puis exécuter le témoin MITM; commit atomique.
4. Durcir manifest et Gradle, ajouter le script de build obfusqué, verrouiller les dépendances et corriger la documentation; commit atomique.
5. Rejouer formatage, analyse, tests ciblés, garde statique et build release avec une clé éphémère non debug; tenter le parcours sur appareil physique s’il devient disponible.

## 8. Test Strategy

- `test/security_configuration_test.dart`: l’ancien arbre doit échouer car sept clients omettent le callback, le manifest autorise HTTP clair et Gradle référence la signature debug; l’arbre corrigé exige une unique construction centralisée avec callback, aucune sérialisation sensible, R8 et script obfusqué.
- `test/host_key_trust_service_test.dart`: première empreinte acceptée et stockée; même empreinte acceptée sans prompt; empreinte MITM différente refusée sans réécriture ni second prompt; refus initial non mémorisé; confirmations concurrentes mutualisées.
- `test/secure_storage_migration_test.dart`: mot de passe config et profils migré avant nettoyage; panne du coffre conserve le legacy; historique legacy réécrit sans `arguments` ni `output`; rétention limitée à 50 métadonnées.
- Vérifications: `dart format --output=none --set-exit-if-changed lib test`; `flutter analyze`; `flutter test test/host_key_trust_service_test.dart test/secure_storage_migration_test.dart test/security_configuration_test.dart`; `flutter test` avec le rouge de layout préexistant signalé séparément s’il subsiste; `tool/build_android_release.sh` avec clé éphémère non debug; inspection APK/AAB et symboles.

## 9. Risk and Impact Analysis

- La migration est le risque principal: aucune suppression en clair avant confirmation de l’écriture dans le coffre; tests d’échec obligatoires.
- Les deux dépendants directs de `SshConfig.load` doivent conserver le chargement initial et les rafraîchissements de barre de statut.
- Les trois dépendants directs de `saveProfiles` doivent préserver ajout, mise à jour et suppression, y compris la suppression de la clé sécurisée d’un profil supprimé.
- `_launchSkill` doit continuer à enregistrer statut et durée, mais les écrans ne doivent plus proposer une sortie persistée après redémarrage.
- Les sept connexions doivent recevoir le même service de confiance dans `HomeScreen` pour éviter plusieurs dialogues concurrents.
- Retirer `config.local.json` de l’asset rompt volontairement l’initialisation par fichier contenant un secret; le formulaire Paramètres devient le chemin d’entrée sûr.
- Exiger une vraie clé release rend les builds release sans credentials volontairement rouges; le build de preuve utilisera une clé locale éphémère et ne sera pas distribué.
- Aucun appareil Android physique n’est actuellement visible (`flutter devices --machine` ne retourne que Linux); ce critère ne pourra pas être déclaré vérifié sans changement externe.

## 10. Files Expected to Change

| File | Symbols | Reason |
| ---- | ------- | ------ |
| `lib/services/secure_storage_service.dart` | `SecretStore`, `FlutterSecretStore` | Coffre injectable |
| `lib/services/host_key_trust_service.dart` | `HostKeyChallenge`, `HostKeyTrustService.verify` | TOFU et refus MITM |
| `lib/services/ssh_client_factory.dart` | `SshClientFactory.create` | Callback obligatoire unique |
| `lib/models/ssh_config.dart` | `toJson`, `load`, `save` | Migration du mot de passe |
| `lib/models/ssh_profile.dart` | `toJson`, `fromJson` | Métadonnées sans secret |
| `lib/services/profile_service.dart` | `loadProfiles`, `saveProfiles`, CRUD | Migration et suppression du coffre |
| `lib/models/skill_history.dart` | `toJson`, `fromJson`, `load`, `add` | Historique sans contenu sensible |
| `lib/screens/home_screen.dart` | `_init`, `_confirmHostKey`, connexions | UX TOFU et migration au démarrage |
| `lib/services/skill_discovery.dart` | `discover` | Fabrique SSH sûre |
| `lib/services/ssh_service.dart` | `connect`, `testConnection` | Fabrique SSH sûre |
| `lib/services/usage_service.dart` | `fetch` | Fabrique SSH sûre |
| `pubspec.yaml`, `pubspec.lock`, `.gitignore` | dépendances/assets | Coffre et verrouillage |
| `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml` | release/application | Signature, R8, cleartext, backup |
| `tool/build_android_release.sh`, `README.md` | build/docs | Obfuscation obligatoire et usage sûr |
| `test/host_key_trust_service_test.dart`, `test/secure_storage_migration_test.dart`, `test/security_configuration_test.dart` | nouveaux tests | Témoins régression |

## 11. Reusable Implementation Context

```yaml
implementation_context:
  task_summary: "Sécuriser les clés d’hôte SSH, les secrets locaux, l’historique et le build Android de Nexterm pour ops#2175."
  acceptance_criteria:
    - "Première clé affichée et confirmée, clé identique acceptée ensuite, clé différente refusée."
    - "Témoin MITM rouge avant et vert après correction."
    - "Mots de passe migrés vers Keystore/Keychain sans nouvelle copie SharedPreferences."
    - "Historique limité à 50 métadonnées sans arguments ni sortie brute."
    - "Release sans signature debug, R8 actif, chemin de build avec obfuscation et symboles."
    - "Trafic HTTP clair interdit."
    - "Connexion et reconnexion validées sur appareil physique."
  evidence_provenance:
    schema_version: 2
    head_commit: "102375b68173a55d5e018e8427a207b4d111cbf2"
    generated_plan_path: "docs/plans/2026-09-14-gitnexus-plan-secure-ssh-storage.md"
    global_dirty_digest:
      algorithm: "sha256"
      canonicalization: "gitnexus-evidence-provenance-v2 NUL-framed UTF-8 records"
      value: "0a9c85780067d9afcd0764f307b60891e3cee927ee11eaeb5ec7826d10fd82cd"
    cited_path_manifest:
      - {path: "README.md", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:4eba1ae98ef23c0ece7e376055ed9a445f2424a5ec8776860f54ffa15d5ded7f", index_digest: "sha256:4eba1ae98ef23c0ece7e376055ed9a445f2424a5ec8776860f54ffa15d5ded7f", worktree_digest: "sha256:4eba1ae98ef23c0ece7e376055ed9a445f2424a5ec8776860f54ffa15d5ded7f", untracked_digest: absent}
      - {path: "android/app/build.gradle.kts", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:80465fee2a12656b0eb3f369af7ad4677d6847ad24b316144d740316e4db2d2d", index_digest: "sha256:80465fee2a12656b0eb3f369af7ad4677d6847ad24b316144d740316e4db2d2d", worktree_digest: "sha256:80465fee2a12656b0eb3f369af7ad4677d6847ad24b316144d740316e4db2d2d", untracked_digest: absent}
      - {path: "android/app/src/main/AndroidManifest.xml", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:15bb5e5d44a9dfdce66d29ebea72138eb8c77d2ca9a85254a6cf11fa366fdbf8", index_digest: "sha256:15bb5e5d44a9dfdce66d29ebea72138eb8c77d2ca9a85254a6cf11fa366fdbf8", worktree_digest: "sha256:15bb5e5d44a9dfdce66d29ebea72138eb8c77d2ca9a85254a6cf11fa366fdbf8", untracked_digest: absent}
      - {path: "lib/models/skill_history.dart", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:92d786b4290f3a0df3f7a82f3e1cb883550ae470ef97a3f427f80af279066e5a", index_digest: "sha256:92d786b4290f3a0df3f7a82f3e1cb883550ae470ef97a3f427f80af279066e5a", worktree_digest: "sha256:92d786b4290f3a0df3f7a82f3e1cb883550ae470ef97a3f427f80af279066e5a", untracked_digest: absent}
      - {path: "lib/models/ssh_config.dart", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:3a817bb9539985bc62f682920bbf9b2c64ff3bd06451fa2355a3386bc6ce0924", index_digest: "sha256:3a817bb9539985bc62f682920bbf9b2c64ff3bd06451fa2355a3386bc6ce0924", worktree_digest: "sha256:3a817bb9539985bc62f682920bbf9b2c64ff3bd06451fa2355a3386bc6ce0924", untracked_digest: absent}
      - {path: "lib/models/ssh_profile.dart", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:fc8e2e65a45d7b559aacbde449bf6d88362cb99f20fe4978ffa62d62b211aab7", index_digest: "sha256:fc8e2e65a45d7b559aacbde449bf6d88362cb99f20fe4978ffa62d62b211aab7", worktree_digest: "sha256:fc8e2e65a45d7b559aacbde449bf6d88362cb99f20fe4978ffa62d62b211aab7", untracked_digest: absent}
      - {path: "lib/screens/home_screen.dart", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:a74af974c6932d93e64034f3d57719f19b163cd609b1b8663c7b210b10212b0b", index_digest: "sha256:a74af974c6932d93e64034f3d57719f19b163cd609b1b8663c7b210b10212b0b", worktree_digest: "sha256:a74af974c6932d93e64034f3d57719f19b163cd609b1b8663c7b210b10212b0b", untracked_digest: absent}
      - {path: "lib/screens/settings_screen.dart", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:078b6a7fb444235549b8f8dc30d031c5ba08c85724a625b0a63a1f68e10ed315", index_digest: "sha256:078b6a7fb444235549b8f8dc30d031c5ba08c85724a625b0a63a1f68e10ed315", worktree_digest: "sha256:078b6a7fb444235549b8f8dc30d031c5ba08c85724a625b0a63a1f68e10ed315", untracked_digest: absent}
      - {path: "lib/services/host_key_trust_service.dart", object_kind: {head: absent, index: absent, worktree: absent, untracked: absent}, state: absent, rename_from: null, rename_to: null, head_digest: absent, index_digest: absent, worktree_digest: absent, untracked_digest: absent}
      - {path: "lib/services/profile_service.dart", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:e26193359d680803313f8f09c2c5de316d56286f00be0fdd51574cb6e2fbd99d", index_digest: "sha256:e26193359d680803313f8f09c2c5de316d56286f00be0fdd51574cb6e2fbd99d", worktree_digest: "sha256:e26193359d680803313f8f09c2c5de316d56286f00be0fdd51574cb6e2fbd99d", untracked_digest: absent}
      - {path: "lib/services/secure_storage_service.dart", object_kind: {head: absent, index: absent, worktree: absent, untracked: absent}, state: absent, rename_from: null, rename_to: null, head_digest: absent, index_digest: absent, worktree_digest: absent, untracked_digest: absent}
      - {path: "lib/services/skill_discovery.dart", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:fb699c49990535166bdf660e05ac754c64b323f027e127db4dc8915197233613", index_digest: "sha256:fb699c49990535166bdf660e05ac754c64b323f027e127db4dc8915197233613", worktree_digest: "sha256:fb699c49990535166bdf660e05ac754c64b323f027e127db4dc8915197233613", untracked_digest: absent}
      - {path: "lib/services/ssh_client_factory.dart", object_kind: {head: absent, index: absent, worktree: absent, untracked: absent}, state: absent, rename_from: null, rename_to: null, head_digest: absent, index_digest: absent, worktree_digest: absent, untracked_digest: absent}
      - {path: "lib/services/ssh_service.dart", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:14a8f2dc6d6e5c876107087db3f787a42c243161a44977551fddb8278535311d", index_digest: "sha256:14a8f2dc6d6e5c876107087db3f787a42c243161a44977551fddb8278535311d", worktree_digest: "sha256:14a8f2dc6d6e5c876107087db3f787a42c243161a44977551fddb8278535311d", untracked_digest: absent}
      - {path: "lib/services/usage_service.dart", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:39d616ced4bf5f4eb6aef5655e06ad5f53cd88f66a5d77eb6eef605f792659ba", index_digest: "sha256:39d616ced4bf5f4eb6aef5655e06ad5f53cd88f66a5d77eb6eef605f792659ba", worktree_digest: "sha256:39d616ced4bf5f4eb6aef5655e06ad5f53cd88f66a5d77eb6eef605f792659ba", untracked_digest: absent}
      - {path: "pubspec.lock", object_kind: {head: absent, index: absent, worktree: absent, untracked: regular}, state: untracked, rename_from: null, rename_to: null, head_digest: absent, index_digest: absent, worktree_digest: absent, untracked_digest: "sha256:6161871eb9d28b097168d21fd6bf1a4ee1434873d046eaec8ba42a04cb5fe00a"}
      - {path: "pubspec.yaml", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:7233412bca3e71956462e79c506beeda7ec37d4830b7cf4107d2067e1f9d6ec6", index_digest: "sha256:7233412bca3e71956462e79c506beeda7ec37d4830b7cf4107d2067e1f9d6ec6", worktree_digest: "sha256:7233412bca3e71956462e79c506beeda7ec37d4830b7cf4107d2067e1f9d6ec6", untracked_digest: absent}
      - {path: "test/host_key_trust_service_test.dart", object_kind: {head: absent, index: absent, worktree: absent, untracked: absent}, state: absent, rename_from: null, rename_to: null, head_digest: absent, index_digest: absent, worktree_digest: absent, untracked_digest: absent}
      - {path: "test/secure_storage_migration_test.dart", object_kind: {head: absent, index: absent, worktree: absent, untracked: absent}, state: absent, rename_from: null, rename_to: null, head_digest: absent, index_digest: absent, worktree_digest: absent, untracked_digest: absent}
      - {path: "test/security_configuration_test.dart", object_kind: {head: absent, index: absent, worktree: absent, untracked: absent}, state: absent, rename_from: null, rename_to: null, head_digest: absent, index_digest: absent, worktree_digest: absent, untracked_digest: absent}
      - {path: "test/widget_test.dart", object_kind: {head: regular, index: regular, worktree: regular, untracked: absent}, state: clean, rename_from: null, rename_to: null, head_digest: "sha256:ced78260909649917baeeb7a757ce6d71774f6a11b7073f83882afbae0219b69", index_digest: "sha256:ced78260909649917baeeb7a757ce6d71774f6a11b7073f83882afbae0219b69", worktree_digest: "sha256:ced78260909649917baeeb7a757ce6d71774f6a11b7073f83882afbae0219b69", untracked_digest: absent}
      - {path: "tool/build_android_release.sh", object_kind: {head: absent, index: absent, worktree: absent, untracked: absent}, state: absent, rename_from: null, rename_to: null, head_digest: absent, index_digest: absent, worktree_digest: absent, untracked_digest: absent}
  primary_symbols:
    - {symbol: "SshConfig.load/save", file: "lib/models/ssh_config.dart", lines: "39-60", role: "Migration du mot de passe singleton"}
    - {symbol: "ProfileService.saveProfiles", file: "lib/services/profile_service.dart", lines: "16-19", role: "Frontière de persistance des profils"}
    - {symbol: "SkillHistoryService.add/load", file: "lib/models/skill_history.dart", lines: "77-107", role: "Frontière de persistance historique"}
    - {symbol: "_HomeScreenState._launchSkill", file: "lib/screens/home_screen.dart", lines: "126-265", role: "Connexion active et production de l’historique"}
    - {symbol: "SshService.connect", file: "lib/services/ssh_service.dart", lines: "12-100", role: "Connexion profil réutilisable"}
  related_symbols:
    - {symbol: "_HomeScreenState._init", relationship: "CALLS SshConfig.load", relevance: "Migration et première connexion"}
    - {symbol: "_HomeScreenState._buildStatusBar", relationship: "CALLS SshConfig.load", relevance: "Rafraîchissement config"}
    - {symbol: "ProfileService.addProfile/updateProfile/deleteProfile", relationship: "CALLS saveProfiles", relevance: "CRUD à préserver"}
    - {symbol: "_HomeScreenState._showSkillDialog", relationship: "CALLS _launchSkill", relevance: "Déclenchement UI"}
  execution_path:
    - "HomeScreen charge et migre la configuration locale."
    - "Une connexion reçoit la clé avant authentification."
    - "Le service TOFU compare le coffre ou demande confirmation au premier contact."
    - "La fabrique ne crée le client que muni du callback de vérification."
    - "Les exécutions terminées persistent uniquement statut, dates et identifiants non sensibles."
  pdg_constraints:
    - {description: "Aucune arête Dart exploitable après indexation PDG; ordre confirmé par source.", affected_statements: ["lib/models/ssh_config.dart:39", "lib/services/profile_service.dart:16"], implementation_consequence: "Écrire le coffre avant de nettoyer SharedPreferences."}
    - {description: "TOFU strict.", affected_statements: ["lib/screens/home_screen.dart:157", "lib/services/ssh_service.dart:38"], implementation_consequence: "Ne jamais proposer d’accepter automatiquement une empreinte différente déjà connue."}
  architectural_patterns:
    - {pattern: "Service injectable avec implémentation plateforme", example_location: "lib/services/connectivity_service.dart:5", usage_guidance: "Isoler le canal plateforme derrière une interface testable."}
  files_to_modify:
    - {file: "lib/services/secure_storage_service.dart", symbols: ["SecretStore", "FlutterSecretStore"], intended_change: "Ajouter le coffre natif injectable."}
    - {file: "lib/services/host_key_trust_service.dart", symbols: ["HostKeyChallenge", "HostKeyTrustService.verify"], intended_change: "Ajouter TOFU strict."}
    - {file: "lib/services/ssh_client_factory.dart", symbols: ["SshClientFactory.create"], intended_change: "Centraliser les clients vérifiés."}
    - {file: "lib/models/ssh_config.dart", symbols: ["toJson", "load", "save"], intended_change: "Migrer et retirer le secret sérialisé."}
    - {file: "lib/models/ssh_profile.dart", symbols: ["toJson", "fromJson"], intended_change: "Retirer le secret sérialisé."}
    - {file: "lib/services/profile_service.dart", symbols: ["loadProfiles", "saveProfiles"], intended_change: "Migrer les secrets de profils."}
    - {file: "lib/models/skill_history.dart", symbols: ["toJson", "load", "add"], intended_change: "Persister uniquement les métadonnées."}
    - {file: "lib/screens/home_screen.dart", symbols: ["_init", "_confirmHostKey", "_launchSkill", "_connectTerminalSession", "_killSession"], intended_change: "Câbler migrations et TOFU."}
    - {file: "lib/services/skill_discovery.dart", symbols: ["discover"], intended_change: "Utiliser la fabrique sûre."}
    - {file: "lib/services/ssh_service.dart", symbols: ["connect", "testConnection"], intended_change: "Utiliser la fabrique sûre."}
    - {file: "lib/services/usage_service.dart", symbols: ["fetch"], intended_change: "Utiliser la fabrique sûre."}
    - {file: "pubspec.yaml", symbols: [], intended_change: "Ajouter le coffre et retirer l’asset secret."}
    - {file: "android/app/build.gradle.kts", symbols: ["release"], intended_change: "Vraie signature et R8."}
    - {file: "android/app/src/main/AndroidManifest.xml", symbols: ["application"], intended_change: "Interdire cleartext et backup de coffre."}
    - {file: "tool/build_android_release.sh", symbols: [], intended_change: "Build obfusqué avec symboles."}
  tests:
    - {file: "test/host_key_trust_service_test.dart", scenarios: ["première clé + acceptation -> confiance écrite", "même clé -> succès sans prompt", "clé MITM différente -> refus sans prompt ni écriture", "refus initial -> aucune confiance", "deux premières connexions -> un seul prompt"]}
    - {file: "test/secure_storage_migration_test.dart", scenarios: ["legacy config/profil -> coffre puis JSON nettoyé", "panne coffre -> legacy conservé", "ancien historique sensible -> métadonnées seulement", "51 ajouts -> 50 entrées"]}
    - {file: "test/security_configuration_test.dart", scenarios: ["aucun SSHClient hors fabrique", "fabrique contient onVerifyHostKey", "manifest sans cleartext", "Gradle sans debug et avec R8", "script contient --obfuscate et --split-debug-info"]}
  verification_commands:
    - "dart format --output=none --set-exit-if-changed lib test"
    - "flutter analyze"
    - "flutter test test/host_key_trust_service_test.dart test/secure_storage_migration_test.dart test/security_configuration_test.dart"
    - "flutter test"
    - "tool/build_android_release.sh"
    - "flutter devices --machine"
  risks:
    - "Perte de secrets si le legacy est effacé avant écriture coffre."
    - "Prompts TOFU concurrents lors du rafraîchissement initial."
    - "Build release volontairement bloqué sans clé valide."
    - "Test widget préexistant rouge et aucun appareil physique visible."
  assumptions:
    - "Vérifier que flutter_secure_storage 11.x est compatible avec le minSdk résolu avant build; lancer flutter pub get puis Gradle."
    - "Vérifier que le callback dartssh2 reste FutureOr<bool>(String, Uint8List) après résolution du lockfile."
    - "Vérifier que key.properties de production n’est pas présent dans le dépôt et reste ignoré."
  open_questions:
    - "Un appareil Android physique doit être connecté pour la preuve finale connexion/reconnexion."
    - "Aucune CI, release GitHub ni cible de déploiement/store n’existe actuellement; la preuve production dépend d’un canal de distribution externe non documenté."
  avoid:
    - "Ne pas accepter une nouvelle empreinte après qu’une confiance existe pour le même host:port."
    - "Ne pas supprimer une copie legacy avant confirmation de l’écriture coffre."
    - "Ne pas persister arguments ou sortie terminal brute, même dans le coffre."
    - "Ne pas embarquer config.local.json."
    - "Ne pas corriger le défaut de layout préexistant hors périmètre ops#2175."
```

## 12. Assumptions and Open Questions

- [assumed] `flutter_secure_storage` 11.x reste compatible avec le minSdk effectif; le build Gradle le confirmera.
- [verified] Le callback dartssh2 2.17.1 est `FutureOr<bool> Function(String type, Uint8List fingerprint)` et expose une empreinte MD5 seulement.
- [verified] Aucun `key.properties`, keystore tracké, workflow, release GitHub ou déploiement Nexterm n’existe au commit épinglé.
- [verified] Aucun appareil Android physique n’est visible au moment du plan. La preuve appareil et toute promotion restent ouvertes tant qu’un appareil ou canal de distribution n’est pas fourni.
- Suivi différé: moderniser l’authentification SSH par clé et corriger le test widget/layout relèvent d’issues séparées.

## 13. Definition of Done

- Les tests de sécurité échouent sur l’ancien comportement et passent sur le nouveau.
- Toutes les créations de client passent par le callback TOFU centralisé.
- Les migrations préservent les secrets en cas d’échec et retirent toutes les valeurs sensibles de `SharedPreferences` après succès.
- Les entrées d’historique nouvelles et migrées ne contiennent ni arguments ni sortie brute.
- Le manifest interdit HTTP clair et backup Android; Gradle refuse debug/missing signing, active minification et réduction des ressources.
- Un AAB release obfusqué est produit avec symboles séparés au moyen d’une clé locale non debug.
- Formatage, analyse et tests ciblés sont verts; le rouge préexistant de la suite complète est explicitement isolé s’il subsiste.
- Connexion initiale, reconnexion avec même clé et refus d’une clé changée sont observés sur appareil physique.
- PR poussée, contrôles suivis, fusion/promotion prouvée si un canal existe, bilan ajouté à ops#2175; issue fermée uniquement quand tous les critères, dont appareil physique, sont observés.
