import 'package:cloud_firestore/cloud_firestore.dart';

class Appointment {
  final String id;
  final String doctor;
  final String place;
  final DateTime dateTime;
  final String notes;

  const Appointment({
    required this.id,
    required this.doctor,
    required this.place,
    required this.dateTime,
    required this.notes,
  });

  factory Appointment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final ts = d['dateTime'];
    return Appointment(
      id: doc.id,
      doctor: d['doctor'] as String? ?? '',
      place: d['place'] as String? ?? '',
      dateTime: ts is Timestamp ? ts.toDate() : DateTime.now(),
      notes: d['notes'] as String? ?? '',
    );
  }
}