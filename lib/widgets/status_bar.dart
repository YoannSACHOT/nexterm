import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';

class StatusBar extends StatelessWidget {
  final ConnectivityStatus? status;
  final bool isChecking;
  final VoidCallback onRefresh;

  const StatusBar({
    super.key,
    required this.status,
    required this.isChecking,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.black87,
      child: Row(
        children: [
          _indicator(
            label: 'VPN',
            connected: status?.vpnConnected,
            checking: isChecking,
          ),
          const SizedBox(width: 16),
          _indicator(
            label: 'SSH',
            connected: status?.sshReachable,
            checking: isChecking,
          ),
          const Spacer(),
          if (isChecking)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white54,
              ),
            )
          else
            GestureDetector(
              onTap: onRefresh,
              child: const Icon(Icons.refresh, color: Colors.white54, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _indicator({
    required String label,
    required bool? connected,
    required bool checking,
  }) {
    Color color;
    IconData icon;

    if (checking || connected == null) {
      color = Colors.grey;
      icon = Icons.circle_outlined;
    } else if (connected) {
      color = Colors.greenAccent;
      icon = Icons.check_circle;
    } else {
      color = Colors.redAccent;
      icon = Icons.cancel;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
