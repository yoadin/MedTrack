import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/appointment.dart';
import '../models/medication.dart';
import '../utils/format.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  // Appointment reminders: the evening before, and one hour before.
  static const _dayBeforeHour = 18;
  static const _dayBeforeMinute = 0;
  static const _appointmentIdBase = 100000;

  // Medications with an end date (or a later start) get one reminder per day.
  static const _maxDaysAhead = 60;
  static const _maxMedicationReminders = 400;

  List<Medication> _meds = const [];
  List<Appointment> _appointments = const [];
  Future<void> _queue = Future.value();

  NotificationDetails _detailsFor(String body) => NotificationDetails(
        android: AndroidNotificationDetails(
          'med_reminders',
          'Medication reminders',
          channelDescription: 'Reminders to take your medicines',
          importance: Importance.high,
          priority: Priority.high,
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
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  Future<void> syncMedications(List<Medication> meds) {
    _meds = meds;
    return _rebuild();
  }

  Future<void> syncAppointments(List<Appointment> appointments) {
    _appointments = appointments;
    return _rebuild();
  }

  /// Removes every reminder (used on log out).
  Future<void> clearAll() {
    _meds = const [];
    _appointments = const [];
    return _rebuild();
  }

  // Rebuilds run one after another, each using the latest lists.
  Future<void> _rebuild() {
    _queue = _queue.then((_) => _doRebuild());
    return _queue;
  }

  /// Next moment (today or tomorrow) when the clock shows [hhmm].
  tz.TZDateTime _nextInstance(String hhmm) {
    final parts = hhmm.split(':');
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day,
        int.parse(parts[0]), int.parse(parts[1]));
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  /// One reminder moment per day per dose time, only on days when the
  /// medication is active, for the next [_maxDaysAhead] days.
  List<tz.TZDateTime> _datedReminders(Medication med, tz.TZDateTime now) {
    final result = <tz.TZDateTime>[];
    for (var i = 0; i < _maxDaysAhead; i++) {
      final day = DateTime(now.year, now.month, now.day + i);
      if (!med.isActiveOn(day)) continue;
      for (final time in med.times) {
        final p = time.split(':');
        final when = tz.TZDateTime(tz.local, day.year, day.month, day.day,
            int.parse(p[0]), int.parse(p[1]));
        if (when.isAfter(now)) result.add(when);
      }
    }
    return result;
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    bool daily = false,
  }) {
    debugPrint('Scheduling "$title" at $when');
    return _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: _detailsFor(body),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: daily ? DateTimeComponents.time : null,
    );
  }

  Future<void> _doRebuild() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancelAll();
      final now = tz.TZDateTime.now(tz.local);

      // Medications
      var id = 0;
      for (final med in _meds) {
        if (med.hasEnded) continue;

        final body = [
          if (med.dose.isNotEmpty) 'Dose: ${med.dose}',
          if (med.form.isNotEmpty) med.form,
        ].join(' · ');
        final text = body.isEmpty ? 'Tap to open MedTrack' : body;
        final title = 'Time to take ${med.name}';

        if (med.endDate == null && !med.startsLater) {
          // Ongoing: one repeating daily reminder per dose time.
          for (final time in med.times) {
            if (id >= _maxMedicationReminders) break;
            await _schedule(
              id: id++,
              title: title,
              body: text,
              when: _nextInstance(time),
              daily: true,
            );
          }
        } else {
          // Has an end date (or starts later): one reminder per day.
          for (final when in _datedReminders(med, now)) {
            if (id >= _maxMedicationReminders) break;
            await _schedule(id: id++, title: title, body: text, when: when);
          }
        }
      }

      // Appointments: the evening before, and one hour before.
      var apptId = _appointmentIdBase;
      for (final a in _appointments) {
        final when = tz.TZDateTime.from(a.dateTime, tz.local);
        final info = [
          'With ${a.doctor} at ${formatTime(a.dateTime)}',
          if (a.place.isNotEmpty) a.place,
        ].join(' · ');

        final prev = when.subtract(const Duration(days: 1));
        final dayBefore = tz.TZDateTime(tz.local, prev.year, prev.month,
            prev.day, _dayBeforeHour, _dayBeforeMinute);
        if (dayBefore.isAfter(now)) {
          await _schedule(
            id: apptId,
            title: 'Appointment tomorrow',
            body: info,
            when: dayBefore,
          );
        }

        final hourBefore = when.subtract(const Duration(hours: 1));
        if (hourBefore.isAfter(now)) {
          await _schedule(
            id: apptId + 1,
            title: 'Appointment in 1 hour',
            body: info,
            when: hourBefore,
          );
        }
        apptId += 2;
      }

      final pending = await _plugin.pendingNotificationRequests();
      debugPrint('Reminders pending: ${pending.length}');
    } catch (e, st) {
      debugPrint('Reminder scheduling FAILED: $e\n$st');
    }
  }
}