import 'dart:async';
import 'dart:io';

/// Vérifie la connectivité VPN et la disponibilité SSH.
class ConnectivityService {
  /// Vérifie si le VPN est actif en cherchant une interface tun/wg.
  Future<bool> isVpnConnected() async {
    try {
      final interfaces = await NetworkInterface.list();
      return interfaces.any((iface) =>
          iface.name.startsWith('tun') ||
          iface.name.startsWith('wg') ||
          iface.name.startsWith('utun'));
    } catch (_) {
      return false;
    }
  }

  /// Vérifie si le host SSH est joignable (TCP connect sur le port).
  Future<bool> isSshReachable(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Statut complet : VPN + SSH.
  Future<ConnectivityStatus> checkStatus(String sshHost, int sshPort) async {
    final vpn = await isVpnConnected();
    final ssh = await isSshReachable(sshHost, sshPort);
    return ConnectivityStatus(vpnConnected: vpn, sshReachable: ssh);
  }
}

class ConnectivityStatus {
  final bool vpnConnected;
  final bool sshReachable;

  const ConnectivityStatus({
    required this.vpnConnected,
    required this.sshReachable,
  });

  bool get allGood => vpnConnected && sshReachable;
}
