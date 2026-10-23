import 'package:cloud_firestore/cloud_firestore.dart';

/// "2026-10-23" -> DateTime(2026, 10, 23), or null if missing.
DateTime? _parseDay(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  final p = value.split('-');
  if (p.length != 3) return null;
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

class Medication {
  final String id;
  final String name;
  final String dose;
  final String form;
  final List<String> times; // 24h format, e.g. "08:00"
  final String notes;
  final DateTime? createdAt;
  final DateTime? startDate; // null on older medications
  final DateTime? endDate; // null = no end date (ongoing)

  const Medication({
    required this.id,
    required this.name,
    required this.dose,
    required this.form,
    required this.times,
    required this.notes,
    this.createdAt,
    this.startDate,
    this.endDate,
  });

  factory Medication.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final created = d['createdAt'];
    return Medication(
      id: doc.id,
      name: d['name'] as String? ?? '',
      dose: d['dose'] as String? ?? '',
      form: d['form'] as String? ?? '',
      times: List<String>.from(d['times'] as List? ?? const []),
      notes: d['notes'] as String? ?? '',
      createdAt: created is Timestamp ? created.toDate() : null,
      startDate: _parseDay(d['startDate']),
      endDate: _parseDay(d['endDate']),
    );
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Is this medication scheduled on [day]? Dates are inclusive.
  bool isActiveOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (startDate != null && d.isBefore(startDate!)) return false;
    if (endDate != null && d.isAfter(endDate!)) return false;
    return true;
  }

  /// The end date has passed.
  bool get hasEnded => endDate != null && _today().isAfter(endDate!);

  /// The start date is still in the future.
  bool get startsLater => startDate != null && startDate!.isAfter(_today());
}