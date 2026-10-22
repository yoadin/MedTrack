import 'dart:async';

import 'package:flutter/material.dart';

import '../models/appointment.dart';
import '../services/appointment_service.dart';
import '../services/notification_service.dart';
import '../utils/format.dart';
import 'add_appointment_screen.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  final _service = AppointmentService();
  late final Stream<List<Appointment>> _stream = _service.watchAll();
  StreamSubscription<List<Appointment>>? _reminderSub;

  @override
  void initState() {
    super.initState();
    // Rebuild appointment reminders whenever the list changes.
    _reminderSub = _service.watchAll().listen(
          (list) => NotificationService.instance.syncAppointments(list),
          onError: (Object e) => debugPrint('Appointments stream: $e'),
        );
  }

  @override
  void dispose() {
    _reminderSub?.cancel();
    super.dispose();
  }

  Future<void> _confirmDelete(Appointment a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete appointment?'),
        content: Text('Remove the appointment with ${a.doctor}?'),
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
    if (ok == true) _service.delete(a.id);
  }

  void _edit(Appointment a) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddAppointmentScreen(appointment: a)),
    );
  }

  Widget _tile(Appointment a, {required bool past}) {
    final scheme = Theme.of(context).colorScheme;
    final lines = [
      '${formatDate(a.dateTime)} · ${formatTime(a.dateTime)}',
      if (a.place.isNotEmpty) a.place,
    ];
    return Card(
      child: ListTile(
        onTap: () => _edit(a),
        leading: Icon(
          Icons.event,
          color: past ? scheme.onSurfaceVariant : scheme.primary,
        ),
        title: Text(a.doctor),
        subtitle: Text(lines.join('\n')),
        isThreeLine: lines.length > 1,
        trailing: IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _confirmDelete(a),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Appointments')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddAppointmentScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add appointment'),
      ),
      body: StreamBuilder<List<Appointment>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Could not load.\n${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          if (all.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No appointments yet.\nTap "Add appointment" to start.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final now = DateTime.now();
          final upcoming = all.where((a) => !a.dateTime.isBefore(now)).toList();
          final past =
              all.where((a) => a.dateTime.isBefore(now)).toList().reversed.toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text('Upcoming',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              if (upcoming.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text('No upcoming appointments.'),
                ),
              for (final a in upcoming) _tile(a, past: false),
              if (past.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text('Past',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                for (final a in past) _tile(a, past: true),
              ],
            ],
          );
        },
      ),
    );
  }
}