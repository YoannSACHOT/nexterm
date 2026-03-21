import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static int _nextId = 0;

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'skill_done',
          'Skills terminées',
          description: 'Notification quand une skill est terminée',
          importance: Importance.high,
        ));
  }

  static Future<void> show({
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'skill_done',
          'Skills terminées',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
