import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';
import '../services/notification_service.dart';
import 'disclaimer.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  /// Closes the drawer, then opens [screen].
  void _go(BuildContext context, Widget screen) {
    final nav = Navigator.of(context);
    nav.pop(); // close the drawer
    nav.push(MaterialPageRoute(builder: (_) => screen));
  }

  void _showAbout(BuildContext context) {
    final nav = Navigator.of(context);
    nav.pop();
    showDisclaimer(nav.context);
  }

  Future<void> _logout(BuildContext context) async {
    final nav = Navigator.of(context);
    nav.pop();
    final ok = await showDialog<bool>(
      context: nav.context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Reminders on this phone will stop until you log in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Remove this user's reminders from the phone before signing out.
    await NotificationService.instance.clearAll();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.userChanges(),
            initialData: FirebaseAuth.instance.currentUser,
            builder: (context, snap) {
              final user = snap.data;
              final name = (user?.displayName ?? '').trim();
              final email = user?.email ?? '';
              final source = name.isNotEmpty ? name : email;
              final initial = source.isEmpty ? '?' : source[0].toUpperCase();
              return UserAccountsDrawerHeader(
                accountName: Text(name.isEmpty ? 'MedTrack user' : name),
                accountEmail: Text(email),
                currentAccountPicture: CircleAvatar(
                  child: Text(initial, style: const TextStyle(fontSize: 28)),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('My profile'),
            onTap: () => _go(context, const ProfileScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () => _go(context, const SettingsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About and disclaimer'),
            onTap: () => _showAbout(context),
          ),
          const Spacer(),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              onTap: () => _logout(context),
            ),
          ),
        ],
      ),
    );
  }
}