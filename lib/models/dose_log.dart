import 'package:cloud_firestore/cloud_firestore.dart';

class DoseLog {
  final String id; // medicationId_date_time
  final String medicationId;
  final String medicationName;
  final String dose;
  final String form;
  final String date; // "2026-10-22"
  final String time; // "08:00"
  final String status; // "taken" or "skipped"

  const DoseLog({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.dose,
    required this.form,
    required this.date,
    required this.time,
    required this.status,
  });

  factory DoseLog.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return DoseLog(
      id: doc.id,
      medicationId: d['medicationId'] as String? ?? '',
      medicationName: d['medicationName'] as String? ?? '',
      dose: d['dose'] as String? ?? '',
      form: d['form'] as String? ?? '',
      date: d['date'] as String? ?? '',
      time: d['time'] as String? ?? '',
      status: d['status'] as String? ?? '',
    );
  }
}