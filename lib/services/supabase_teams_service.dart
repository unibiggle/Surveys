import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseTeamsService {
  final SupabaseClient _client;
  SupabaseTeamsService(this._client);

  Future<List<Map<String, dynamic>>> listTeams() async {
    final res = await _client
        .from('teams')
        .select('id,name,created_at,created_by')
        .order('created_at')
        .then((value) => value as List<dynamic>);
    return res.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createTeam(String name) async {
    final uid = _client.auth.currentUser?.id;
    final res = await _client
        .from('teams')
        .insert({'name': name, if (uid != null) 'created_by': uid})
        .select('id,name')
        .single();
    final map = res as Map<String, dynamic>;
    try {
      if (uid != null) {
        // Ensure creator has membership (in case trigger is blocked by RLS)
        await addOrUpdateMember(teamId: map['id'] as String, userId: uid, role: 'owner');
      }
    } catch (_) {
      // Ignore if trigger already created membership or if RPC is blocked; listing will still work if membership exists.
    }
    return map;
  }

  Future<List<Map<String, dynamic>>> listMembers(String teamId) async {
    final res = await _client
        .from('memberships')
        .select('user_id, role, created_at')
        .eq('team_id', teamId)
        .order('created_at')
        .then((value) => value as List<dynamic>);
    return res.cast<Map<String, dynamic>>();
  }

  Future<void> addOrUpdateMember({required String teamId, required String userId, String role = 'member'}) async {
    await _client.rpc('add_team_member', params: {
      'p_team_id': teamId,
      'p_user_id': userId,
      'p_role': role,
    });
  }

  Future<void> removeMember({required String teamId, required String userId}) async {
    await _client.rpc('remove_team_member', params: {
      'p_team_id': teamId,
      'p_user_id': userId,
    });
  }

  Future<void> deleteTeam(String id) async {
    await _client.from('teams').delete().eq('id', id);
  }
}
