import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/session_providers.dart';
import '../services/sync_service.dart';
import 'teams/teams_page.dart';
import 'templates/templates_page.dart';
import 'surveys/surveys_page.dart';
bool _didInitialSync = false;

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTeam = ref.watch(selectedTeamProvider);
    if (selectedTeam != null && !_didInitialSync) {
      _didInitialSync = true;
      // Pull templates on first entry to persist across reinstalls
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final sync = ref.read(syncServiceProvider);
        await sync.pullTemplates();
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Surveys${selectedTeam != null ? ' • ${selectedTeam.name}' : ''}'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () async {
              final client = Supabase.instance.client;
              final uid = client.auth.currentUser?.id;
              if (uid == null) return;
              final currentName = await client
                  .from('profiles')
                  .select('full_name')
                  .eq('id', uid)
                  .maybeSingle()
                  .then((v) => (v?['full_name'] as String?) ?? '');
              final ctrl = TextEditingController(text: currentName);
              final name = await showDialog<String>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Edit profile'),
                  content: TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
                    textCapitalization: TextCapitalization.words,
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
                  ],
                ),
              );
              if (name == null) return;
              await client.from('profiles').upsert({'id': uid, 'full_name': name});
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
              }
            },
            icon: const Icon(Icons.person),
          ),
          IconButton(
            tooltip: 'Sync',
            onPressed: () async {
              final sync = ref.read(syncServiceProvider);
              await sync.pullTemplates();
              await sync.pushPendingOps();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sync complete')));
              }
            },
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Change team',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const TeamsPage()));
            },
            icon: const Icon(Icons.group),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              ref.read(selectedTeamProvider.notifier).state = null;
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selectedTeam == null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Text('No team selected. Pick or create a team.'),
              ),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TemplatesPage()),
              ),
              icon: const Icon(Icons.view_list),
              label: const Text('Templates'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SurveysPage()),
              ),
              icon: const Icon(Icons.assignment),
              label: const Text('Surveys'),
            ),
          ],
        ),
      ),
    );
  }
}
