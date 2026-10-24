import 'dart:async';
import 'package:flutter/material.dart';

import '../models/medication.dart';
import '../services/medication_service.dart';
import '../services/notification_service.dart';
import '../utils/format.dart';
import 'add_medication_screen.dart';
import '../widgets/app_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = MedicationService();
  late final Stream<List<Medication>> _stream = _service.watchAll();
  StreamSubscription<List<Medication>>? _reminderSub;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.requestPermissions();
    // Rebuild all reminders whenever the medication list changes
    // (add, edit, delete). Works offline too, from Firestore's cache.
        _reminderSub = _service.watchAll().listen(
          (meds) => NotificationService.instance.syncMedications(meds),
          onError: (Object e) => debugPrint('Medication stream: $e'),
        );
  }

  @override
  void dispose() {
    _reminderSub?.cancel();
    super.dispose();
  }


  Future<void> _confirmDelete(Medication med) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete medication?'),
        content: Text('Remove ${med.name} from your list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _service.delete(med.id);
    }
  }

  String? _rangeText(Medication med) {
    if (med.hasEnded) return 'Ended ${formatDate(med.endDate!)}';
    if (med.startsLater) return 'Starts ${formatDate(med.startDate!)}';
    if (med.endDate != null) return 'Until ${formatDate(med.endDate!)}';
    return null;
  }

  Widget _medCard(Medication med, {bool finished = false}) {
    final scheme = Theme.of(context).colorScheme;
    final details =
        [med.dose, med.form].where((s) => s.isNotEmpty).join(' · ');
    final range = _rangeText(med);

    return Card(
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddMedicationScreen(medication: med),
          ),
        ),
        leading: Icon(
          Icons.medication_outlined,
          color: finished ? scheme.onSurfaceVariant : null,
        ),
        title: Text(med.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.isNotEmpty) Text(details),
            if (range != null) Text(range),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in med.times)
                  Chip(
                    label: Text(t),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _confirmDelete(med),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('My medications'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddMedicationScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add medication'),
      ),
      body: StreamBuilder<List<Medication>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load medications.\n${snap.error}'),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final meds = snap.data!;
          if (meds.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No medications yet.\nTap "Add medication" to start.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final active = meds.where((m) => !m.hasEnded).toList();
          final finished = meds.where((m) => m.hasEnded).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              for (final med in active) _medCard(med),
              if (finished.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text('Finished',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                for (final med in finished) _medCard(med, finished: true),
              ],
            ],
          );
        },
      ),
    );
  }
}