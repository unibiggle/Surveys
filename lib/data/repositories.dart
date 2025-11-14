import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/template_schema.dart';
import 'app_database.dart';
import 'providers.dart';

class TemplateRepository {
  TemplateRepository(this._db, this._uuid);
  final AppDatabase _db;
  final Uuid _uuid;

  Stream<List<Template>> watchAllTemplates() {
    return (_db.select(_db.templates)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]) )
        .watch();
  }

  Future<String> createOrUpdateTemplate(TemplateSchema schema, {String? teamId, bool published = false}) async {
    final id = schema.id.isEmpty ? _uuid.v4() : schema.id;
    await _db.upsertTemplate(
      id: id,
      name: schema.name,
      version: schema.version,
      schemaJson: TemplateSchema.encode(schema),
      teamId: teamId,
      published: published,
    );
    // Enqueue for sync with Supabase
    await _db.enqueueOp(
      entity: 'templates',
      entityId: id,
      op: 'upsert',
      payloadJson: jsonEncode({
        'id': id,
        'team_id': teamId,
        'name': schema.name,
        'version': schema.version,
        'schema_json': schema.toJson(),
        'published': published,
      }),
    );
    return id;
  }

  Future<TemplateSchema?> getTemplateSchema(String templateId) async {
    final row = await (_db.select(_db.templates)..where((t) => t.id.equals(templateId))).getSingleOrNull();
    if (row == null) return null;
    return TemplateSchema.decode(row.schemaJson);
  }

  Future<void> deleteTemplate(String id) async {
    await _db.deleteTemplate(id);
  }
}

class SurveyRepository {
  SurveyRepository(this._db, this._uuid);
  final AppDatabase _db;
  final Uuid _uuid;

  Stream<List<Survey>> watchAllSurveys() {
    return (_db.select(_db.surveys)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]) )
        .watch();
  }

  Future<String> startSurvey({required Template template, String? teamId, String? assigneeUserId}) async {
    final id = _uuid.v4();
    await _db.createSurvey(
      id: id,
      templateId: template.id,
      templateVersion: template.version,
      teamId: teamId,
      assigneeUserId: assigneeUserId,
    );
    // Enqueue for sync (actual team_id will be resolved client-side when pushing)
    await _db.enqueueOp(
      entity: 'surveys',
      entityId: id,
      op: 'upsert',
      payloadJson: jsonEncode({
        'id': id,
        'template_id': template.id,
        'template_version': template.version,
        'status': 'in_progress',
        if (teamId != null) 'team_id': teamId,
        if (assigneeUserId != null) 'assignee_user_id': assigneeUserId,
      }),
    );
    return id;
  }

  Future<void> saveResponse({
    required String surveyId,
    required String questionId,
    required dynamic value, // will be encoded to json
    double? score,
    String? responseId,
  }) async {
    final id = responseId ?? _uuid.v4();
    await _db.upsertResponse(
      id: id,
      surveyId: surveyId,
      questionId: questionId,
      valueJson: jsonEncode(value),
      score: score,
    );
    await _db.enqueueOp(
      entity: 'responses',
      entityId: id,
      op: 'upsert',
      payloadJson: jsonEncode({
        'id': id,
        'survey_id': surveyId,
        'question_id': questionId,
        'value_json': value,
        'score': score,
      }),
    );
  }
}

// Providers
final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  return TemplateRepository(ref.read(databaseProvider), ref.read(uuidProvider));
});

final surveyRepositoryProvider = Provider<SurveyRepository>((ref) {
  return SurveyRepository(ref.read(databaseProvider), ref.read(uuidProvider));
});
