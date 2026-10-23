import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/medication.dart';
import '../models/dose_log.dart';

class DoseLogService {
  CollectionReference<Map<String, dynamic>> get _col {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('doseLogs');
  }

  /// "2026-10-22"
  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Same medication + date + time always gives the same ID.
  static String logId(String medId, String date, String time) =>
      '${medId}_${date}_${time.replaceAll(':', '')}';

  /// Map of logId -> status ("taken" / "skipped") for one day.
  Stream<Map<String, String>> watchDay(String date) {
    return _col.where('date', isEqualTo: date).snapshots().map(
          (snap) => {
            for (final d in snap.docs)
              d.id: d.data()['status'] as String? ?? '',
          },
        );
  }

  Future<void> mark({
    required Medication med,
    required String date,
    required String time,
    required String status, // 'taken' or 'skipped'
  }) {
    return _col.doc(logId(med.id, date, time)).set({
      'medicationId': med.id,
      'medicationName': med.name,
      'dose': med.dose,
      'form': med.form,
      'date': date,
      'time': time,
      'status': status,
      'loggedAt': FieldValue.serverTimestamp(),
    });
  }

    /// All logs from [date] ("2026-10-16") up to today.
  Future<List<DoseLog>> fetchSince(String date) async {
    final snap = await _col.where('date', isGreaterThanOrEqualTo: date).get();
    return snap.docs.map(DoseLog.fromDoc).toList();
  }

  Future<void> undo(String logId) => _col.doc(logId).delete();
}