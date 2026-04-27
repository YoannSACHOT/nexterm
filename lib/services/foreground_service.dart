import 'package:flutter/services.dart';

/// Bridge vers le foreground service Android qui maintient le processus
/// vivant pendant que des sessions SSH sont ouvertes — empêche l'OS de
/// killer l'app quand elle passe en arrière-plan.
class ForegroundService {
  static const _channel =
      MethodChannel('com.jixter.nexterm/foreground_service');

  static int _count = 0;
  static bool _running = false;

  /// Synchronise l'état du service avec le nombre de sessions actives.
  /// Appeler à chaque ouverture/fermeture/changement d'état.
  static Future<void> sync(int activeCount, {String? status}) async {
    _count = activeCount;
    try {
      if (activeCount > 0) {
        if (!_running) {
          await _channel.invokeMethod('start', {
            'count': activeCount,
            if (status != null) 'status': status,
          });
          _running = true;
        } else {
          await _channel.invokeMethod('update', {
            'count': activeCount,
            if (status != null) 'status': status,
          });
        }
      } else if (_running) {
        await _channel.invokeMethod('stop');
        _running = false;
      }
    } on PlatformException {
      // Service indisponible — pas critique
    } on MissingPluginException {
      // Plateforme non supportée (web, desktop)
    }
  }

  static Future<void> stopAll() async {
    _count = 0;
    if (!_running) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    _running = false;
  }
}
