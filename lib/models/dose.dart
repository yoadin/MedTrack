import 'medication.dart';

enum DoseStatus { upcoming, missed, taken, skipped }

/// One scheduled dose of one medication on the current day.
class Dose {
  final String key; // ID of its document in doseLogs
  final Medication med;
  final String time; // "08:00"
  final DoseStatus status;

  const Dose({
    required this.key,
    required this.med,
    required this.time,
    required this.status,
  });
}