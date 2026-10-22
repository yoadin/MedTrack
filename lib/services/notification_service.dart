import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Addis_Ababa'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );
  }

  Future<void> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  Future<void> scheduleTest() async {
    await _plugin.zonedSchedule(
      id: 999,
      title: 'MedTrack',
      body: 'Test reminder: time to take your medicine',
      scheduledDate:
          tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10)),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'med_reminders',
          'Medication reminders',
          channelDescription: 'Reminders to take your medicines',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}