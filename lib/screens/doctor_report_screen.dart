import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/appointment.dart';
import '../models/dose_log.dart';
import '../models/medication.dart';
import '../services/appointment_service.dart';
import '../services/dose_log_service.dart';
import '../services/medication_service.dart';
import '../utils/format.dart';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Dose counts for one medication over the chosen period.
class _MedStats {
  final String name;
  final String details;
  final Medication? med; // null = the medication was deleted
  int scheduled = 0;
  int taken = 0;
  int skipped = 0;
  int missed = 0;

  _MedStats({required this.name, required this.details, this.med});

  int get percent =>
      scheduled == 0 ? 0 : ((taken / scheduled) * 100).round().clamp(0, 100);
}

class _ReportData {
  final DateTime now;
  final DateTime start;
  final List<_MedStats> stats;
  final List<Appointment> appointments;

  const _ReportData({
    required this.now,
    required this.start,
    required this.stats,
    required this.appointments,
  });

  int get scheduled => stats.fold(0, (s, m) => s + m.scheduled);
  int get taken => stats.fold(0, (s, m) => s + m.taken);
  int get skipped => stats.fold(0, (s, m) => s + m.skipped);
  int get missed => stats.fold(0, (s, m) => s + m.missed);
  int get percent =>
      scheduled == 0 ? 0 : ((taken / scheduled) * 100).round().clamp(0, 100);
}

class DoctorReportScreen extends StatefulWidget {
  const DoctorReportScreen({super.key});

  @override
  State<DoctorReportScreen> createState() => _DoctorReportScreenState();
}

class _DoctorReportScreenState extends State<DoctorReportScreen> {
  final _medService = MedicationService();
  final _logService = DoseLogService();
  final _apptService = AppointmentService();

  int _days = 7;
  late Future<_ReportData> _future = _load(_days);
  bool _exporting = false;

  void _reload() {
    setState(() {
      _future = _load(_days);
    });
  }

  Future<void> _sharePdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final data = await _future; // the report currently on screen
      final bytes = await _buildPdf(data, _days);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'medtrack-report-${dayKey(DateTime.now())}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create the PDF ($e).')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<_ReportData> _load(int days) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - (days - 1));

    final results = await Future.wait([
      _medService.fetchAll(),
      _logService.fetchSince(DoseLogService.dateKey(start)),
      _apptService.fetchAll(),
    ]);
    final meds = results[0] as List<Medication>;
    final logs = results[1] as List<DoseLog>;
    final appointments = results[2] as List<Appointment>;

    meds.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final logsById = {for (final l in logs) l.id: l};
    final currentIds = meds.map((m) => m.id).toSet();
    final stats = <_MedStats>[];

    // Current medications
    // Current medications
    for (final med in meds) {
      // Skip medications that ended before this period began.   // ← NEW
      if (med.endDate != null && med.endDate!.isBefore(start))
        continue; // ← NEW

      final slots = <String>{};

      // Doses that were due in the period and are already in the past.
      for (var i = 0; i < days; i++) {
        final day = DateTime(start.year, start.month, start.day + i);
        if (!med.isActiveOn(day)) continue; // ← NEW
        for (final time in med.times) {
          final p = time.split(':');
          final scheduled = DateTime(
            day.year,
            day.month,
            day.day,
            int.parse(p[0]),
            int.parse(p[1]),
          );
          final created = med.createdAt;
          final pastDue =
              scheduled.isBefore(now) &&
              (created == null || !created.isAfter(scheduled));
          if (pastDue) {
            slots.add(
              DoseLogService.logId(med.id, DoseLogService.dateKey(day), time),
            );
          }
        }
      }
      // Anything logged also counts (for example a dose taken early).
      for (final l in logs.where((l) => l.medicationId == med.id)) {
        slots.add(l.id);
      }

      final s = _MedStats(
        name: med.name,
        details: [med.dose, med.form].where((x) => x.isNotEmpty).join(' · '),
        med: med,
      );
      s.scheduled = slots.length;
      for (final id in slots) {
        final status = logsById[id]?.status;
        if (status == 'taken') {
          s.taken++;
        } else if (status == 'skipped') {
          s.skipped++;
        } else {
          s.missed++;
        }
      }
      stats.add(s);
    }

    // Deleted medications: only what was logged is known.
    final removed = <String, _MedStats>{};
    for (final l in logs.where((l) => !currentIds.contains(l.medicationId))) {
      final s = removed.putIfAbsent(
        l.medicationId,
        () => _MedStats(
          name: l.medicationName,
          details: [l.dose, l.form].where((x) => x.isNotEmpty).join(' · '),
        ),
      );
      s.scheduled++;
      if (l.status == 'taken') {
        s.taken++;
      } else if (l.status == 'skipped') {
        s.skipped++;
      }
    }
    stats.addAll(removed.values);

    return _ReportData(
      now: now,
      start: start,
      stats: stats,
      appointments: appointments
          .where((a) => !a.dateTime.isBefore(start))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor report'),
        actions: [
          IconButton(
            tooltip: 'Share as PDF',
            icon: _exporting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _exporting ? null : _sharePdf,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 days')),
                ButtonSegment(value: 14, label: Text('14 days')),
                ButtonSegment(value: 30, label: Text('30 days')),
              ],
              selected: {_days},
              onSelectionChanged: (s) {
                _days = s.first;
                _reload();
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<_ReportData>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not build the report.\n${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return _ReportView(data: snap.data!, days: _days);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  final _ReportData data;
  final int days;

  const _ReportView({required this.data, required this.days});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final displayName = (FirebaseAuth.instance.currentUser?.displayName ?? '')
        .trim();
    final who = [
      if (displayName.isNotEmpty) displayName,
      if (email.isNotEmpty) email,
    ].join(' | ');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Prepared ${formatDate(data.now)}${who.isEmpty ? '' : ' | $who'}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        _SummaryCard(data: data, days: days),
        const SizedBox(height: 20),
        Text('Medicines', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (data.stats.isEmpty)
          const Text('No medications recorded.')
        else
          for (final s in data.stats) _MedCard(stats: s),
        const SizedBox(height: 20),
        Text('Appointments', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (data.appointments.isEmpty)
          const Text('No appointments in this period.')
        else
          for (final a in data.appointments)
            Card(
              child: ListTile(
                leading: const Icon(Icons.event),
                title: Text(a.doctor),
                subtitle: Text(
                  [
                    '${formatDate(a.dateTime)} · ${formatTime(a.dateTime)}',
                    if (a.place.isNotEmpty) a.place,
                    if (a.notes.isNotEmpty) 'Notes: ${a.notes}',
                  ].join('\n'),
                ),
                isThreeLine: a.place.isNotEmpty || a.notes.isNotEmpty,
              ),
            ),
        const SizedBox(height: 24),
        Text(
          'This report only shows what was recorded in MedTrack. '
          'It is not medical advice.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final _ReportData data;
  final int days;

  const _SummaryCard({required this.data, required this.days});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime(data.now.year, data.now.month, data.now.day);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last $days days', style: theme.textTheme.titleMedium),
            Text(
              '${formatDate(data.start)} – ${formatDate(today)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Count(
                    label: 'Taken',
                    value: '${data.taken}',
                    color: Colors.green.shade700,
                  ),
                ),
                Expanded(
                  child: _Count(label: 'Skipped', value: '${data.skipped}'),
                ),
                Expanded(
                  child: _Count(
                    label: 'Missed',
                    value: '${data.missed}',
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: data.scheduled == 0 ? 0 : data.taken / data.scheduled,
            ),
            const SizedBox(height: 6),
            Text(
              data.scheduled == 0
                  ? 'No scheduled doses in this period.'
                  : '${data.taken} of ${data.scheduled} scheduled doses '
                        'recorded as taken (${data.percent}%)',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MedCard extends StatelessWidget {
  final _MedStats stats;

  const _MedCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final med = stats.med;
    final removed = med == null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(stats.name, style: theme.textTheme.titleMedium),
            if (stats.details.isNotEmpty) Text(stats.details),
            if (med != null && med.times.isNotEmpty)
              Text('Times: ${med.times.join(', ')}'),
            if (med != null) Text(_periodText(med)),
            if (med != null && med.notes.isNotEmpty)
              Text('Notes: ${med.notes}'),
            if (removed)
              Text(
                'This medication was deleted from the app. '
                'Only recorded doses are shown.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Count(
                    label: 'Taken',
                    value: '${stats.taken}',
                    color: Colors.green.shade700,
                    small: true,
                  ),
                ),
                Expanded(
                  child: _Count(
                    label: 'Skipped',
                    value: '${stats.skipped}',
                    small: true,
                  ),
                ),
                Expanded(
                  child: _Count(
                    label: 'Missed',
                    value: removed ? '–' : '${stats.missed}',
                    color: theme.colorScheme.error,
                    small: true,
                  ),
                ),
                Expanded(
                  child: _Count(
                    label: 'Taken %',
                    value: removed ? '–' : '${stats.percent}%',
                    small: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool small;

  const _Count({
    required this.label,
    required this.value,
    this.color,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = small
        ? theme.textTheme.titleMedium
        : theme.textTheme.headlineSmall;
    return Column(
      children: [
        Text(value, style: style?.copyWith(color: color)),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

String _periodText(Medication med) {
  final start = med.startDate ?? med.createdAt;
  final parts = <String>[];
  if (start != null) parts.add('From ${formatDate(start)}');
  final end = med.endDate;
  if (end == null) {
    parts.add('ongoing');
  } else {
    parts.add('${med.hasEnded ? 'ended' : 'until'} ${formatDate(end)}');
  }
  return parts.join(' · ');
}

pw.Widget _pdfCount(String label, String value) => pw.Column(
  children: [
    pw.Text(
      value,
      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
    ),
    pw.Text(
      label,
      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
    ),
  ],
);

Future<Uint8List> _buildPdf(_ReportData data, int days) async {
  final email = FirebaseAuth.instance.currentUser?.email ?? '';
  final today = DateTime(data.now.year, data.now.month, data.now.day);

  // Optional font so notes written in Amharic can be printed.
  // If the font file is not in the project, only Latin text shows.
  final fallback = <pw.Font>[];
  try {
    final bytes = await rootBundle.load(
      'assets/fonts/NotoSansEthiopic-Regular.ttf',
    );
    fallback.add(pw.Font.ttf(bytes));
  } catch (_) {}

  final doc = pw.Document(
    title: 'MedTrack medicine report',
    theme: pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
      fontFallback: fallback,
    ),
  );

  final heading = pw.TextStyle(
    fontSize: 15,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.teal700,
  );
  const small = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: (ctx) => pw.Column(
        children: [
          pw.Divider(color: PdfColors.grey300),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'This report only shows what was recorded in MedTrack. '
                  'It is not medical advice.',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
              pw.Text(
                'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ],
      ),
      build: (ctx) => [
        pw.Text(
          'MedTrack medicine report',
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.teal700,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Prepared ${formatDate(data.now)}${email.isEmpty ? '' : ' | $email'}',
          style: small,
        ),
        pw.Text(
          'Period: ${formatDate(data.start)} - ${formatDate(today)} '
          '(last $days days)',
          style: small,
        ),
        pw.SizedBox(height: 14),

        // Summary
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _pdfCount('Taken', '${data.taken}'),
              _pdfCount('Skipped', '${data.skipped}'),
              _pdfCount('Missed', '${data.missed}'),
              _pdfCount('Taken %', '${data.percent}%'),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          data.scheduled == 0
              ? 'No scheduled doses in this period.'
              : '${data.taken} of ${data.scheduled} scheduled doses recorded '
                    'as taken.',
          style: small,
        ),
        pw.SizedBox(height: 16),

        // Medicines
        pw.Text('Medicines', style: heading),
        pw.SizedBox(height: 6),
        if (data.stats.isEmpty)
          pw.Text('No medications recorded.')
        else
          pw.Table(
            columnWidths: const {0: pw.FlexColumnWidth()},
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              for (final s in data.stats)
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            s.name,
                            style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (s.details.isNotEmpty)
                            pw.Text(s.details.replaceAll(' · ', ', ')),
                          if (s.med != null && s.med!.times.isNotEmpty)
                            pw.Text('Times: ${s.med!.times.join(', ')}'),
                          if (s.med != null) pw.Text(_periodText(s.med!)),
                          if (s.med != null && s.med!.notes.isNotEmpty)
                            pw.Text('Notes: ${s.med!.notes}'),
                          if (s.med == null)
                            pw.Text(
                              'Deleted from the app; only recorded doses are shown.',
                              style: pw.TextStyle(
                                fontStyle: pw.FontStyle.italic,
                              ),
                            ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            s.med == null
                                ? 'Taken ${s.taken}, skipped ${s.skipped}'
                                : 'Taken ${s.taken}, skipped ${s.skipped}, '
                                      'missed ${s.missed} '
                                      '(taken ${s.percent}% of ${s.scheduled} scheduled)',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        pw.SizedBox(height: 10),

        // Appointments
        pw.Text('Appointments', style: heading),
        pw.SizedBox(height: 6),
        if (data.appointments.isEmpty)
          pw.Text('No appointments in this period.'),
        for (final a in data.appointments)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${formatDate(a.dateTime)} ${formatTime(a.dateTime)} - '
                  '${a.doctor}${a.place.isNotEmpty ? ', ${a.place}' : ''}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                if (a.notes.isNotEmpty) pw.Text('Notes: ${a.notes}'),
              ],
            ),
          ),
      ],
    ),
  );

  return doc.save();
}
