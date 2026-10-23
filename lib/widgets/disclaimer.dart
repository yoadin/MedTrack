import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _points = [
  'MedTrack helps you keep a record of your medicines, reminders and '
      'appointments. It does not give medical advice, diagnose conditions '
      'or suggest doses.',
  'Doses and times in the app are only what you entered. Always follow '
      'your doctor\'s or pharmacist\'s instructions.',
  'Reminders can fail (phone battery settings, no signal, a switched-off '
      'phone). Do not rely on them alone for medicines that are critical.',
  'Medicine name suggestions come from the Ethiopian Essential Medicines '
      'List (2024). They are a typing aid, not a guide to what you should '
      'take.',
  'Your data is stored in your account on Google Firebase and is protected '
      'by your login and security rules, so only you can read it.',
  'If you feel unwell or have an emergency, contact a health worker or '
      'your nearest health facility.',
];

String _key() =>
    'disclaimer_accepted_${FirebaseAuth.instance.currentUser?.uid}';

Future<bool> hasAcceptedDisclaimer() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key()) ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> _saveAccepted() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(), true);
  } catch (_) {
    // If saving fails, the dialog simply shows again next time.
  }
}

/// [mustAccept] true: first-time version, cannot be dismissed without
/// tapping "I understand". false: read-only version with a Close button.
Future<void> showDisclaimer(BuildContext context,
    {bool mustAccept = false}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !mustAccept,
    builder: (ctx) => PopScope(
      canPop: !mustAccept,
      child: AlertDialog(
        title: Text(mustAccept ? 'Before you start' : 'About MedTrack'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in _points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(child: Text(p)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              if (mustAccept) await _saveAccepted();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(mustAccept ? 'I understand' : 'Close'),
          ),
        ],
      ),
    ),
  );
}