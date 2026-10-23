import 'dart:async';

import 'package:flutter/material.dart';

import '../models/dose.dart';
import '../models/medication.dart';
import '../services/dose_log_service.dart';
import '../services/medication_service.dart';
import 'doctor_report_screen.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final _medService = MedicationService();
  final _logService = DoseLogService();
  late final Stream<List<Medication>> _medStream = _medService.watchAll();

  DateTime _now = DateTime.now();
  late String _date = DoseLogService.dateKey(_now);
  late Stream<Map<String, String>> _logStream = _logService.watchDay(_date);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Refresh every minute so doses move from "upcoming" to "missed",
    // and switch to the new day at midnight.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      final date = DoseLogService.dateKey(now);
      setState(() {
        _now = now;
        if (date != _date) {
          _date = date;
          _logStream = _logService.watchDay(date);
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  List<Dose> _buildDoses(List<Medication> meds, Map<String, String> logs) {
    final nowKey = _hhmm(_now);
    final doses = <Dose>[];

    for (final med in meds) {
      for (final time in med.times) {
        final key = DoseLogService.logId(med.id, _date, time);
        final logged = logs[key];

        final DoseStatus status;
        if (logged == 'taken') {
          status = DoseStatus.taken;
        } else if (logged == 'skipped') {
          status = DoseStatus.skipped;
        } else if (time.compareTo(nowKey) < 0) {
          status = DoseStatus.missed;
        } else {
          status = DoseStatus.upcoming;
        }

        // Don't count a dose as missed if the medication was added after it.
        if (status == DoseStatus.missed && med.createdAt != null) {
          final p = time.split(':');
          final scheduled = DateTime(_now.year, _now.month, _now.day,
              int.parse(p[0]), int.parse(p[1]));
          if (med.createdAt!.isAfter(scheduled)) continue;
        }

        doses.add(Dose(key: key, med: med, time: time, status: status));
      }
    }

    doses.sort((a, b) => a.time.compareTo(b.time));
    return doses;
  }

  // Not awaited on purpose: Firestore saves on the phone immediately and
  // syncs later, so this also works offline.
  void _mark(Dose dose, String status) {
    _logService
        .mark(med: dose.med, date: _date, time: dose.time, status: status)
        .catchError((Object e) => debugPrint('Could not save dose: $e'));
  }

  void _undo(Dose dose) {
    _logService
        .undo(dose.key)
        .catchError((Object e) => debugPrint('Could not undo: $e'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            tooltip: 'Doctor report',
            icon: const Icon(Icons.description_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DoctorReportScreen()),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Medication>>(
        stream: _medStream,
        builder: (context, medSnap) {
          if (medSnap.hasError) {
            return Center(child: Text('Could not load.\n${medSnap.error}'));
          }
          if (!medSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final meds = medSnap.data!;
          if (meds.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No medications yet.\nAdd one in the Medications tab.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return StreamBuilder<Map<String, String>>(
            stream: _logStream,
            builder: (context, logSnap) {
              if (!logSnap.hasData && !logSnap.hasError) {
                return const Center(child: CircularProgressIndicator());
              }
              final doses = _buildDoses(meds, logSnap.data ?? const {});
              if (doses.isEmpty) {
                return const Center(child: Text('No doses for today.'));
              }
              final taken =
                  doses.where((d) => d.status == DoseStatus.taken).length;

              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$taken of ${doses.length} taken today',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: taken / doses.length),
                      ],
                    ),
                  ),
                  for (final dose in doses)
                    _DoseCard(
                      dose: dose,
                      onTaken: () => _mark(dose, 'taken'),
                      onSkip: () => _mark(dose, 'skipped'),
                      onUndo: () => _undo(dose),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _DoseCard extends StatelessWidget {
  final Dose dose;
  final VoidCallback onTaken;
  final VoidCallback onSkip;
  final VoidCallback onUndo;

  const _DoseCard({
    required this.dose,
    required this.onTaken,
    required this.onSkip,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final med = dose.med;
    final details = [med.dose, med.form].where((s) => s.isNotEmpty).join(' · ');

    // (icon, color, label) for each status
    final (icon, color, label) = switch (dose.status) {
      DoseStatus.upcoming => (Icons.schedule, scheme.primary, 'Upcoming'),
      DoseStatus.missed => (Icons.error_outline, scheme.error, 'Missed'),
      DoseStatus.taken => (
          Icons.check_circle,
          Colors.green.shade700,
          'Taken'
        ),
      DoseStatus.skipped => (
          Icons.remove_circle_outline,
          scheme.onSurfaceVariant,
          'Skipped'
        ),
    };

    final isOpen = dose.status == DoseStatus.upcoming ||
        dose.status == DoseStatus.missed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(med.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(
                  dose.status == DoseStatus.missed
                      ? '${dose.time} · Missed'
                      : dose.time,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(details),
              ),
            ],
            const SizedBox(height: 8),
            if (isOpen)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onTaken,
                      icon: const Icon(Icons.check),
                      label: const Text('Taken'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSkip,
                      child: const Text('Skip'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Text(label,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(onPressed: onUndo, child: const Text('Undo')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}