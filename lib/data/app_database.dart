import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// Tables
class Templates extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get teamId => text().nullable()();
  TextColumn get name => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get published => boolean().withDefault(const Constant(false))();
  // JSON-encoded schema for sections/questions/logic
  TextColumn get schemaJson => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Surveys extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get teamId => text().nullable()();
  TextColumn get templateId => text()();
  IntColumn get templateVersion => integer().withDefault(const Constant(1))();
  TextColumn get status => text().withDefault(const Constant('in_progress'))();
  TextColumn get assigneeUserId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Responses extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get surveyId => text()();
  TextColumn get questionId => text()();
  // JSON-encoded value (supports string/number/array/object)
  TextColumn get valueJson => text()();
  RealColumn get score => real().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Attachments extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get surveyId => text()();
  TextColumn get questionId => text()();
  TextColumn get type => text()(); // photo | sketch | signature
  TextColumn get localPath => text().nullable()();
  TextColumn get storagePath => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncOps extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()(); // templates|surveys|responses|attachments
  TextColumn get entityId => text()();
  TextColumn get op => text()(); // upsert|delete
  TextColumn get payloadJson => text()();
  IntColumn get retries => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Templates, Surveys, Responses, Attachments, SyncOps])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // Helpers for common CRUD we'll need immediately
  Future<String> upsertTemplate({
    required String id,
    required String name,
    required int version,
    required String schemaJson,
    String? teamId,
    bool published = false,
  }) async {
    final now = DateTime.now();
    final existing = await (select(templates)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) {
      await into(templates).insert(TemplatesCompanion.insert(
        id: id,
        name: name,
        version: Value(version),
        schemaJson: schemaJson,
        teamId: Value(teamId),
        published: Value(published),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
    } else {
      await (update(templates)..where((t) => t.id.equals(id))).write(TemplatesCompanion(
        name: Value(name),
        version: Value(version),
        schemaJson: Value(schemaJson),
        teamId: Value(teamId),
        published: Value(published),
        updatedAt: Value(now),
      ));
    }
    return id;
  }

  Future<void> deleteTemplate(String id) async {
    await (delete(templates)..where((t) => t.id.equals(id))).go();
  }

  Future<String> createSurvey({
    required String id,
    required String templateId,
    required int templateVersion,
    String? teamId,
    String status = 'in_progress',
    String? assigneeUserId,
  }) async {
    final now = DateTime.now();
    await into(surveys).insert(SurveysCompanion.insert(
      id: id,
      templateId: templateId,
      templateVersion: Value(templateVersion),
      teamId: Value(teamId),
      status: Value(status),
      assigneeUserId: Value(assigneeUserId),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    return id;
  }

  Future<void> upsertResponse({
    required String id,
    required String surveyId,
    required String questionId,
    required String valueJson,
    double? score,
  }) async {
    final existing = await (select(responses)
          ..where((r) => r.id.equals(id)))
        .getSingleOrNull();
    final now = DateTime.now();
    if (existing == null) {
      await into(responses).insert(ResponsesCompanion.insert(
        id: id,
        surveyId: surveyId,
        questionId: questionId,
        valueJson: valueJson,
        score: Value(score),
        updatedAt: Value(now),
      ));
    } else {
      await (update(responses)..where((r) => r.id.equals(id))).write(ResponsesCompanion(
        surveyId: Value(surveyId),
        questionId: Value(questionId),
        valueJson: Value(valueJson),
        score: Value(score),
        updatedAt: Value(now),
      ));
    }
  }

  // Attachments helpers
  Stream<List<Attachment>> watchAttachmentsFor(String surveyId, String questionId) {
    final q = select(attachments)
      ..where((a) => a.surveyId.equals(surveyId) & a.questionId.equals(questionId))
      ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]);
    return q.watch();
  }

  Future<void> addLocalAttachment({
    required String id,
    required String surveyId,
    required String questionId,
    required String type,
    required String localPath,
  }) async {
    await into(attachments).insert(AttachmentsCompanion.insert(
      id: id,
      surveyId: surveyId,
      questionId: questionId,
      type: type,
      localPath: Value(localPath),
    ));
  }

  Future<void> setAttachmentStoragePath({required String id, required String storagePath}) async {
    await (update(attachments)..where((a) => a.id.equals(id))).write(AttachmentsCompanion(
      storagePath: Value(storagePath),
    ));
  }

  Future<void> enqueueOp({required String entity, required String entityId, required String op, required String payloadJson}) async {
    await into(syncOps).insert(SyncOpsCompanion.insert(
      entity: entity,
      entityId: entityId,
      op: op,
      payloadJson: payloadJson,
    ));
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'surveys.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
