import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every SSH client is created by the verified factory', () {
    final constructors = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in RegExp(r'\bSSHClient\s*\(').allMatches(source)) {
        constructors.add('${entity.path}:${match.start}');
      }
    }

    expect(constructors, hasLength(1));
    expect(
      constructors.single,
      startsWith('lib/services/ssh_client_factory.dart:'),
    );
    expect(
      File('lib/services/ssh_client_factory.dart').readAsStringSync(),
      contains('onVerifyHostKey:'),
    );
  });

  test('Android blocks cleartext traffic and device backup', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, isNot(contains('usesCleartextTraffic="true"')));
  });

  test('release configuration never uses debug signing and enables R8', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(gradle, contains('isMinifyEnabled = true'));
    expect(gradle, contains('isShrinkResources = true'));
    expect(gradle, contains('Missing release signing configuration'));
  });

  test('documented release build always obfuscates and emits symbols', () {
    final script = File('tool/build_android_release.sh').readAsStringSync();
    expect(script, contains('--obfuscate'));
    expect(script, contains('--split-debug-info'));
  });
}
