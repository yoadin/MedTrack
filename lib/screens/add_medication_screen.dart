import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:medtrack/services/medication_service.dart';

import '../models/medication.dart'; // add to the imports

class AddMedicationScreen extends StatefulWidget {
  final Medication? medication; // null = adding, not null = editing
  const AddMedicationScreen({super.key, this.medication});

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  static const _forms = [
    'Tablet',
    'Capsule',
    'Syrup',
    'Injection',
    'Drops',
    'Cream / Ointment',
    'Inhaler',
    'Other',
  ];

  final _formKey = GlobalKey<FormState>();
  final _service = MedicationService();
  final _dose = TextEditingController();
  final _notes = TextEditingController();

  TextEditingController? _nameCtrl; // provided by the Autocomplete widget
  List<String> _names = [];
  String _form = _forms.first;
  final List<String> _times = ['08:00'];

  @override
  bool get _isEdit => widget.medication != null;

  @override
  void initState() {
    super.initState();
    _loadNames();
    final med = widget.medication;
    if (med != null) {
      _dose.text = med.dose;
      _notes.text = med.notes;
      if (_forms.contains(med.form)) _form = med.form;
      if (med.times.isNotEmpty) {
        _times
          ..clear()
          ..addAll(med.times);
      }
    }
  }

  Future<void> _loadNames() async {
    final raw = await rootBundle.loadString('assets/medicine_names.json');
    final list = List<String>.from(jsonDecode(raw) as List);
    if (mounted) setState(() => _names = list);
  }

  @override
  void dispose() {
    _dose.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked == null) return;
    final value = _fmt(picked);
    if (!_times.contains(value)) {
      setState(() {
        _times.add(value);
        _times.sort();
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_times.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add at least one time.')));
      return;
    }
    // Not awaited on purpose: Firestore saves to the phone right away and
    // syncs later, so this also works with a poor connection.
    final name = _nameCtrl!.text.trim();
    final times = List<String>.from(_times);
    final Future<void> write = _isEdit
        ? _service.update(
            widget.medication!.id,
            name: name,
            dose: _dose.text.trim(),
            form: _form,
            times: times,
            notes: _notes.text.trim(),
          )
        : _service.add(
            name: name,
            dose: _dose.text.trim(),
            form: _form,
            times: times,
            notes: _notes.text.trim(),
          );
    write.catchError((Object e) => debugPrint('Save failed: $e'));

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit medication' : 'Add medication'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Autocomplete<String>(
              initialValue: TextEditingValue(
                text: widget.medication?.name ?? '',
              ),
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.length < 2) return const Iterable<String>.empty();
                return _names.where((n) => n.toLowerCase().contains(q)).take(8);
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                _nameCtrl = controller;
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Medicine name',
                    helperText: 'Start typing to see suggestions',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter the medicine name'
                      : null,
                );
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dose,
              decoration: const InputDecoration(
                labelText: 'Dose (e.g. 500 mg, 1 tablet, 5 ml)',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter the dose' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _form,
              decoration: const InputDecoration(
                labelText: 'Form',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final f in _forms)
                  DropdownMenuItem(value: f, child: Text(f)),
              ],
              onChanged: (v) => setState(() => _form = v ?? _form),
            ),
            const SizedBox(height: 24),
            Text(
              'Times to take it',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in _times)
                  InputChip(
                    label: Text(t),
                    onDeleted: () => setState(() => _times.remove(t)),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Add time'),
                  onPressed: _addTime,
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                helperText: 'e.g. take after food',
                border: OutlineInputBorder(),
              ),
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
