import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/medication.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  NotificationDetails _detailsFor(String body) => NotificationDetails(
    android: AndroidNotificationDetails(
      'med_reminders',
      'Medication reminders',
      channelDescription: 'Reminders to take your medicines',
      importance: Importance.high,
      priority: Priority.high,
      // Shows the full text when the notification is expanded.
      styleInformation: BigTextStyleInformation(body),
    ),
  );

  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Addis_Ababa'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  /// Next moment (today or tomorrow) when the clock shows [hhmm].
  tz.TZDateTime _nextInstance(String hhmm) {
    final parts = hhmm.split(':');
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  /// Cancels all reminders and schedules a daily one for every time of
  /// every medication.
  Future<void> rescheduleAll(List<Medication> meds) async {
    if (kIsWeb) return;
    await _plugin.cancelAll();

    var id = 0;
          for (final med in meds) {
        final body = [
          if (med.dose.isNotEmpty) 'Dose: ${med.dose}',
          if (med.form.isNotEmpty) med.form,
        ].join(' · ');
        final text = body.isEmpty ? 'Tap to open MedTrack' : body;

        for (final time in med.times) {
          final when = _nextInstance(time);
          debugPrint('Scheduling ${med.name} at $when');
          await _plugin.zonedSchedule(
            id: id++,
            title: 'Time to take ${med.name}',
            body: text,
            scheduledDate: when,
            notificationDetails: _detailsFor(text),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.time,
          );
        }
      }
  }
}
