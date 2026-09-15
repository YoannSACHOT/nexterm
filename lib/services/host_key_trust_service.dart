import 'dart:convert';
import 'dart:typed_data';

import 'secure_storage_service.dart';

typedef HostKeyConfirmation = Future<bool> Function(HostKeyChallenge challenge);

class HostKeyChallenge {
  final String host;
  final int port;
  final String keyType;
  final Uint8List fingerprint;

  const HostKeyChallenge({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
  });

  String get fingerprintText =>
      'MD5:${fingerprint.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(':')}';
}

class HostKeyTrustService {
  final SecretStore _store;
  final Map<String, Future<bool>> _pendingConfirmations = {};

  HostKeyTrustService({SecretStore? store})
    : _store = store ?? defaultSecretStore;

  Future<bool> verify({
    required String host,
    required int port,
    required String keyType,
    required Uint8List fingerprint,
    required HostKeyConfirmation confirm,
  }) async {
    final endpoint = '$host:$port';
    final storageKey = _storageKey(endpoint);
    final candidate = '$keyType:${_fingerprintHex(fingerprint)}';
    final trusted = await _store.read(storageKey);

    if (trusted != null) {
      return trusted == candidate;
    }

    final pending = _pendingConfirmations[endpoint];
    if (pending != null) {
      await pending;
      return await _store.read(storageKey) == candidate;
    }

    final confirmation = _confirmAndStore(
      storageKey: storageKey,
      candidate: candidate,
      challenge: HostKeyChallenge(
        host: host,
        port: port,
        keyType: keyType,
        fingerprint: Uint8List.fromList(fingerprint),
      ),
      confirm: confirm,
    );
    _pendingConfirmations[endpoint] = confirmation;
    try {
      return await confirmation;
    } finally {
      if (identical(_pendingConfirmations[endpoint], confirmation)) {
        _pendingConfirmations.remove(endpoint);
      }
    }
  }

  Future<bool> _confirmAndStore({
    required String storageKey,
    required String candidate,
    required HostKeyChallenge challenge,
    required HostKeyConfirmation confirm,
  }) async {
    if (!await confirm(challenge)) return false;
    await _store.write(storageKey, candidate);
    return true;
  }

  String _storageKey(String endpoint) =>
      'ssh.host.${base64Url.encode(utf8.encode(endpoint))}.fingerprint';

  String _fingerprintHex(Uint8List fingerprint) =>
      fingerprint.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
