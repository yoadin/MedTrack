import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/medication.dart';

class MedicationService {
  CollectionReference<Map<String, dynamic>> get _col {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('medications');
  }

  Stream<List<Medication>> watchAll() {
    return _col
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Medication.fromDoc).toList());
  }

  Future<void> add({
    required String name,
    required String dose,
    required String form,
    required List<String> times,
    required String notes,
  }) {
    return _col.add({
      'name': name,
      'dose': dose,
      'form': form,
      'times': times,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) => _col.doc(id).delete();
}