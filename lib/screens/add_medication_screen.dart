import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/medication.dart';
import '../services/medication_service.dart';
import '../utils/format.dart';

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

  late DateTime _start;
  late DateTime _end;
  bool _hasEnd = false;
  
  List<Medication> _existing = const [];   // ← NEW
  bool _saving = false;                    // ← NEW

  bool get _isEdit => widget.medication != null;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _loadNames();

    var start = _dateOnly(DateTime.now());
    DateTime? end;

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
      start = med.startDate ??
          (med.createdAt != null ? _dateOnly(med.createdAt!) : start);
      end = med.endDate;
    }

    _start = start;
    _hasEnd = end != null;
    _end = end ?? DateTime(start.year, start.month, start.day + 6);
        // Existing medications, used to catch duplicates when saving.
    _service.watchAll().first.then((list) {
      if (mounted) _existing = list;
    }).catchError((Object e) {
      debugPrint('Could not load existing medications: $e');
    });
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

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    setState(() {
      _start = _dateOnly(picked);
      if (_end.isBefore(_start)) _end = _start;
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end.isBefore(_start) ? _start : _end,
      firstDate: _start,
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    setState(() => _end = _dateOnly(picked));
  }

    /// Do the date ranges of [other] and this form overlap?
  bool _overlaps(Medication other) {
    final myEnd = _hasEnd ? _end : null;
    final endsBefore =
        other.endDate != null && other.endDate!.isBefore(_start);
    final startsAfter = myEnd != null &&
        other.startDate != null &&
        other.startDate!.isAfter(myEnd);
    return !endsBefore && !startsAfter;
  }

  /// Another medication with the same name and overlapping dates, if any.
  Medication? _findDuplicate(String name) {
    final wanted = name.trim().toLowerCase();
    for (final other in _existing) {
      if (other.id == widget.medication?.id) continue; // the one being edited
      if (other.name.trim().toLowerCase() != wanted) continue;
      if (_overlaps(other)) return other;
    }
    return null;
  }

  void _showDuplicate(Medication other) {
    final details =
        [other.dose, other.form].where((s) => s.isNotEmpty).join(' · ');
    final range = other.endDate == null
        ? 'ongoing'
        : 'until ${formatDate(other.endDate!)}';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Already in your list'),
        content: Text(
          'You already have ${other.name}'
          '${details.isEmpty ? '' : ' ($details)'}, $range.\n\n'
          'Edit that entry instead. If the treatment has changed, set its '
          'end date first and then add the new one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx); // close the dialog
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => AddMedicationScreen(medication: other),
                ),
              );
            },
            child: const Text('Edit existing'),
          ),
        ],
      ),
    );
  }

    void _save() {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_times.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one time.')),
      );
      return;
    }
    if (_hasEnd && _end.isBefore(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('The end date cannot be before the start date.')),
      );
      return;
    }

    final name = _nameCtrl!.text.trim();

    final duplicate = _findDuplicate(name);
    if (duplicate != null) {
      _showDuplicate(duplicate);
      return;
    }

    _saving = true;
    final times = List<String>.from(_times);
    final endDate = _hasEnd ? _end : null;

    // Not awaited on purpose: Firestore saves to the phone right away and
    // syncs later, so this also works with a poor connection.
    final Future<void> write = _isEdit
        ? _service.update(
            widget.medication!.id,
            name: name,
            dose: _dose.text.trim(),
            form: _form,
            times: times,
            notes: _notes.text.trim(),
            startDate: _start,
            endDate: endDate,
          )
        : _service.add(
            name: name,
            dose: _dose.text.trim(),
            form: _form,
            times: times,
            notes: _notes.text.trim(),
            startDate: _start,
            endDate: endDate,
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
              initialValue:
                  TextEditingValue(text: widget.medication?.name ?? ''),
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.length < 2) return const Iterable<String>.empty();
                return _names
                    .where((n) => n.toLowerCase().contains(q))
                    .take(8);
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
            Text('Times to take it',
                style: Theme.of(context).textTheme.titleMedium),
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
            Text('How long', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickStart,
                icon: const Icon(Icons.play_arrow_outlined),
                label: Text('Starts: ${formatDate(_start)}'),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Set an end date'),
              subtitle: const Text('Leave off if there is no end date'),
              value: _hasEnd,
              onChanged: (v) => setState(() => _hasEnd = v),
            ),
            if (_hasEnd)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickEnd,
                  icon: const Icon(Icons.event),
                  label: Text('Ends: ${formatDate(_end)} (last day)'),
                ),
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