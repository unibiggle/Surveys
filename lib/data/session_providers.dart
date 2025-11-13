import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Stream of auth state changes
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

// Current session (may be null)
final currentSessionProvider = Provider<Session?>((ref) {
  return Supabase.instance.client.auth.currentSession;
});

// Selected team in the app
class SelectedTeam {
  final String id;
  final String name;
  const SelectedTeam({required this.id, required this.name});
}

final selectedTeamProvider = StateProvider<SelectedTeam?>((ref) => null);

