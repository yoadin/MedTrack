import 'package:cloud_firestore/cloud_firestore.dart';

class Medication {
  final String id;
  final String name;
  final String dose;
  final String form;
  final List<String> times; // 24h format, e.g. "08:00"
  final String notes;

  const Medication({
    required this.id,
    required this.name,
    required this.dose,
    required this.form,
    required this.times,
    required this.notes,
  });

  factory Medication.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Medication(
      id: doc.id,
      name: d['name'] as String? ?? '',
      dose: d['dose'] as String? ?? '',
      form: d['form'] as String? ?? '',
      times: List<String>.from(d['times'] as List? ?? const []),
      notes: d['notes'] as String? ?? '',
    );
  }
}