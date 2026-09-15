import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/services/host_key_trust_service.dart';
import 'package:nexterm/services/secure_storage_service.dart';

void main() {
  late MemorySecretStore store;
  late HostKeyTrustService service;

  setUp(() {
    store = MemorySecretStore();
    service = HostKeyTrustService(store: store);
  });

  test('first key is confirmed and the same key reconnects silently', () async {
    var prompts = 0;
    final first = await service.verify(
      host: 'server.example',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: Uint8List.fromList([1, 2, 3]),
      confirm: (_) async {
        prompts++;
        return true;
      },
    );
    final reconnect = await service.verify(
      host: 'server.example',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: Uint8List.fromList([1, 2, 3]),
      confirm: (_) async {
        prompts++;
        return true;
      },
    );

    expect(first, isTrue);
    expect(reconnect, isTrue);
    expect(prompts, 1);
    expect(store.values, hasLength(1));
  });

  test('MITM key change is rejected without prompt or trust rewrite', () async {
    var prompts = 0;
    await service.verify(
      host: 'server.example',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: Uint8List.fromList([1, 2, 3]),
      confirm: (_) async {
        prompts++;
        return true;
      },
    );
    final trustedValue = store.values.values.single;

    final accepted = await service.verify(
      host: 'server.example',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: Uint8List.fromList([9, 9, 9]),
      confirm: (_) async {
        prompts++;
        return true;
      },
    );

    expect(accepted, isFalse);
    expect(prompts, 1);
    expect(store.values.values.single, trustedValue);
  });

  test('rejected first key is not remembered', () async {
    final accepted = await service.verify(
      host: 'server.example',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: Uint8List.fromList([1, 2, 3]),
      confirm: (_) async => false,
    );

    expect(accepted, isFalse);
    expect(store.values, isEmpty);
  });

  test('concurrent first connections share one confirmation', () async {
    final confirmation = Completer<bool>();
    var prompts = 0;

    Future<bool> connect() => service.verify(
      host: 'server.example',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: Uint8List.fromList([1, 2, 3]),
      confirm: (_) {
        prompts++;
        return confirmation.future;
      },
    );

    final first = connect();
    final second = connect();
    await Future<void>.delayed(Duration.zero);
    expect(prompts, 1);
    confirmation.complete(true);
    expect(await Future.wait([first, second]), everyElement(isTrue));
    expect(store.values, hasLength(1));
  });
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
