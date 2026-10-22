import 'package:flutter/material.dart';

import '../models/appointment.dart';
import '../services/appointment_service.dart';
import '../utils/format.dart';

class AddAppointmentScreen extends StatefulWidget {
  final Appointment? appointment; // null = adding, not null = editing
  const AddAppointmentScreen({super.key, this.appointment});

  @override
  State<AddAppointmentScreen> createState() => _AddAppointmentScreenState();
}

class _AddAppointmentScreenState extends State<AddAppointmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = AppointmentService();
  final _doctor = TextEditingController();
  final _place = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _dateTime;

  bool get _isEdit => widget.appointment != null;

  @override
  void initState() {
    super.initState();
    final a = widget.appointment;
    if (a != null) {
      _doctor.text = a.doctor;
      _place.text = a.place;
      _notes.text = a.notes;
      _dateTime = a.dateTime;
    } else {
      final t = DateTime.now().add(const Duration(days: 1));
      _dateTime = DateTime(t.year, t.month, t.day, 9, 0);
    }
  }

  @override
  void dispose() {
    _doctor.dispose();
    _place.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(picked.year, picked.month, picked.day,
          _dateTime.hour, _dateTime.minute);
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(_dateTime.year, _dateTime.month, _dateTime.day,
          picked.hour, picked.minute);
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (!_isEdit && _dateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a future date and time.')),
      );
      return;
    }

    final doctor = _doctor.text.trim();
    final place = _place.text.trim();
    final notes = _notes.text.trim();

    // Not awaited on purpose, so saving also works offline.
    final Future<void> write = _isEdit
        ? _service.update(widget.appointment!.id,
            doctor: doctor, place: place, dateTime: _dateTime, notes: notes)
        : _service.add(
            doctor: doctor, place: place, dateTime: _dateTime, notes: notes);
    write.catchError((Object e) => debugPrint('Save failed: $e'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit appointment' : 'Add appointment'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _doctor,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Doctor or clinic',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter the doctor or clinic'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _place,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Place (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(formatDate(_dateTime)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time),
                  label: Text(formatTime(_dateTime)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                helperText: 'e.g. bring previous results, fasting needed',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'You will get a reminder the evening before and one hour before.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: Text(_isEdit ? 'Save changes' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}