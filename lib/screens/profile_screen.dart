import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/format.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _editName(BuildContext context, User user) async {
    final controller = TextEditingController(text: user.displayName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null) return;

    try {
      await user.updateDisplayName(newName.isEmpty ? null : newName);
      await user.reload();
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'network-request-failed'
                ? 'No internet connection. Try again when you are online.'
                : 'Could not save your name (${e.code}).',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.userChanges(),
        initialData: FirebaseAuth.instance.currentUser,
        builder: (context, snap) {
          final user = snap.data;
          if (user == null) return const SizedBox.shrink();

          final name = (user.displayName ?? '').trim();
          final email = user.email ?? '';
          final created = user.metadata.creationTime;
          final source = name.isNotEmpty ? name : email;
          final initial = source.isEmpty ? '?' : source[0].toUpperCase();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 40,
                  child: Text(initial, style: const TextStyle(fontSize: 32)),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Name'),
                      subtitle: Text(name.isEmpty ? 'Not set' : name),
                      trailing: IconButton(
                        tooltip: 'Edit name',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editName(context, user),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: const Text('Email'),
                      subtitle: Text(email),
                    ),
                    if (created != null) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.event_outlined),
                        title: const Text('Member since'),
                        subtitle: Text(formatDate(created)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}