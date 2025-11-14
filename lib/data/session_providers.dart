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

// Current user's full name from profiles (fallback to auth metadata/email)
final currentUserFullNameProvider = FutureProvider<String?>((ref) async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser?.id;
  if (uid == null) return null;
  try {
    final res = await client.from('profiles').select('full_name').eq('id', uid).maybeSingle();
    final name = (res?['full_name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
  } catch (_) {
    // ignore and fallback
  }
  return client.auth.currentUser?.userMetadata?['full_name'] as String? ?? client.auth.currentUser?.email;
});
