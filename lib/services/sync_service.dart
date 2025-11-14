import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_database.dart';
import '../data/providers.dart';
import '../data/session_providers.dart';

class SyncService {
  SyncService(this._db, this._client, this._ref);
  final AppDatabase _db;
  final SupabaseClient _client;
  final Ref _ref;

  Future<void> pullTemplates() async {
    final team = _ref.read(selectedTeamProvider);
    if (team == null) return;
    final teamRows = await _client
        .from('templates')
        .select('id,team_id,name,version,schema_json,published,updated_at')
        .eq('team_id', team.id);
    final sharedRows = await _client
        .from('templates')
        .select('id,team_id,name,version,schema_json,published,updated_at')
        .filter('team_id', 'is', null);
    final all = <Map<String, dynamic>>[]
      ..addAll((teamRows as List<dynamic>).cast<Map<String, dynamic>>())
      ..addAll((sharedRows as List<dynamic>).cast<Map<String, dynamic>>());
    for (final row in all) {
      await _db.upsertTemplate(
        id: row['id'] as String,
        name: row['name'] as String,
        version: (row['version'] as num).toInt(),
        schemaJson: jsonEncode(row['schema_json']),
        teamId: row['team_id'] as String?,
        published: (row['published'] as bool?) ?? false,
      );
    }
  }

  Future<void> pushPendingOps() async {
    // naive: process sequentially
    final pending = await _db.select(_db.syncOps).get();
    final team = _ref.read(selectedTeamProvider);
    if (team == null) return;
    for (final op in pending) {
      try {
        final payload = jsonDecode(op.payloadJson) as Map<String, dynamic>;
        switch (op.entity) {
          case 'templates':
            // Ensure team_id present (prefer from payload, else selected team)
            payload['team_id'] = payload['team_id'] ?? team.id;
            await _client.from('templates').upsert({
              'id': payload['id'],
              'team_id': payload['team_id'],
              'name': payload['name'],
              'version': payload['version'],
              'schema_json': payload['schema_json'],
              'published': payload['published'] ?? false,
            });
            break;
          case 'surveys':
            payload['team_id'] = team.id;
            await _client.from('surveys').upsert(payload);
            break;
          case 'responses':
            await _client.from('responses').upsert({
              'id': payload['id'],
              'survey_id': payload['survey_id'],
              'question_id': payload['question_id'],
              'value_json': payload['value_json'],
              'score': payload['score'],
            });
            break;
          default:
            debugPrint('Unknown sync entity: ${op.entity}');
        }
        await (_db.delete(_db.syncOps)..where((t) => t.id.equals(op.id))).go();
      } catch (e) {
        debugPrint('Sync op ${op.id} failed: $e');
      }
    }
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref.read(databaseProvider), Supabase.instance.client, ref);
});
