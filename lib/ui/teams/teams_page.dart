import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/session_providers.dart';
import '../../services/supabase_teams_service.dart';

class TeamsPage extends ConsumerStatefulWidget {
  const TeamsPage({super.key});

  @override
  ConsumerState<TeamsPage> createState() => _TeamsPageState();
}

class _TeamsPageState extends ConsumerState<TeamsPage> {
  late final SupabaseTeamsService _svc;
  bool _loading = true;
  List<Map<String, dynamic>> _teams = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _svc = SupabaseTeamsService(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _svc.listTeams();
      setState(() => _teams = rows);
    } catch (e) {
      setState(() => _error = 'Failed to load teams: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createTeam() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New team'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Team name'),
            textCapitalization: TextCapitalization.sentences,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Create')),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    setState(() => _loading = true);
    try {
      final row = await _svc.createTeam(name);
      setState(() => _teams = [..._teams, row]);
    } catch (e) {
      setState(() => _error = 'Failed to create team: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectTeam(Map<String, dynamic> row) {
    ref.read(selectedTeamProvider.notifier).state = SelectedTeam(id: row['id'] as String, name: row['name'] as String);
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      // No-op here: SessionGate listens to selectedTeamProvider and will rebuild to HomePage
    }
  }

  Future<void> _deleteTeam(Map<String, dynamic> row) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final isCreator = uid != null && (row['created_by'] == uid);
    if (!isCreator) {
      setState(() => _error = 'You can only delete teams you created.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete team?'),
        content: Text('This will permanently delete ${row['name']}. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _loading = true);
    try {
      await _svc.deleteTeam(row['id'] as String);
      setState(() => _teams = _teams.where((t) => t['id'] != row['id']).toList());
    } catch (e) {
      setState(() => _error = 'Failed to delete team: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Team')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createTeam,
        icon: const Icon(Icons.group_add),
        label: const Text('New Team'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                  ],
                  if (_teams.isEmpty) const Text('No teams yet. Create one to get started.'),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _teams.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final t = _teams[i];
                        final uid = Supabase.instance.client.auth.currentUser?.id;
                        final canDelete = uid != null && (t['created_by'] == uid);
                        return ListTile(
                          title: Text(t['name'] as String? ?? 'Team'),
                          onTap: () => _selectTeam(t),
                          trailing: canDelete
                              ? IconButton(
                                  tooltip: 'Delete team',
                                  onPressed: () => _deleteTeam(t),
                                  icon: const Icon(Icons.delete_outline),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
