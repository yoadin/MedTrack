import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/appointment.dart';

class AppointmentService {
  CollectionReference<Map<String, dynamic>> get _col {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('appointments');
  }

  Stream<List<Appointment>> watchAll() {
    return _col
        .orderBy('dateTime')
        .snapshots()
        .map((snap) => snap.docs.map(Appointment.fromDoc).toList());
  }

  Future<void> add({
    required String doctor,
    required String place,
    required DateTime dateTime,
    required String notes,
  }) {
    return _col.add({
      'doctor': doctor,
      'place': place,
      'dateTime': Timestamp.fromDate(dateTime),
      'notes': notes,
      'createdAt': Timestamp.now(),
    });
  }

  Future<void> update(
    String id, {
    required String doctor,
    required String place,
    required DateTime dateTime,
    required String notes,
  }) {
    return _col.doc(id).update({
      'doctor': doctor,
      'place': place,
      'dateTime': Timestamp.fromDate(dateTime),
      'notes': notes,
    });
  }

  Future<void> delete(String id) => _col.doc(id).delete();
}