import 'package:dartssh2/dartssh2.dart';

import 'host_key_trust_service.dart';

class SshClientFactory {
  static SSHClient create({
    required SSHSocket socket,
    required String host,
    required int port,
    required String username,
    required String password,
    required HostKeyTrustService hostKeyTrust,
    required HostKeyConfirmation confirmHostKey,
  }) => SSHClient(
    socket,
    username: username,
    onPasswordRequest: () => password,
    onVerifyHostKey: (keyType, fingerprint) => hostKeyTrust.verify(
      host: host,
      port: port,
      keyType: keyType,
      fingerprint: fingerprint,
      confirm: confirmHostKey,
    ),
  );
}
