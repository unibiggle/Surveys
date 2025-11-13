import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import 'package:surveys/ui/draw/sketch_page.dart';

class AttachmentsService {
  final AppDatabase _db;
  final SupabaseClient _client;
  final _uuid = const Uuid();
  AttachmentsService(this._db, this._client);

  Future<void> addPhoto({
    required BuildContext context,
    required String teamId,
    required String surveyId,
    required String questionId,
  }) async {
    String? localPath;
    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      localPath = file.name; // placeholder; we will upload bytes directly
      final id = _uuid.v4();
      await _db.addLocalAttachment(id: id, surveyId: surveyId, questionId: questionId, type: 'photo', localPath: localPath);
      final storagePath = await _uploadBytes(teamId: teamId, surveyId: surveyId, filenameHint: file.name, bytes: file.bytes!);
      await _afterUpload(id: id, surveyId: surveyId, questionId: questionId, storagePath: storagePath, type: 'photo');
      return;
    }
    if (Platform.isIOS || Platform.isAndroid) {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked == null) return;
      localPath = picked.path;
      final id = _uuid.v4();
      await _db.addLocalAttachment(id: id, surveyId: surveyId, questionId: questionId, type: 'photo', localPath: localPath);
      final bytes = await picked.readAsBytes();
      final storagePath = await _uploadBytes(teamId: teamId, surveyId: surveyId, filenameHint: picked.name, bytes: bytes);
      await _afterUpload(id: id, surveyId: surveyId, questionId: questionId, storagePath: storagePath, type: 'photo');
      return;
    }
    // Desktop
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;
    localPath = result.files.first.path!;
    final id = _uuid.v4();
    await _db.addLocalAttachment(id: id, surveyId: surveyId, questionId: questionId, type: 'photo', localPath: localPath);
    final bytes = await File(localPath).readAsBytes();
    final storagePath = await _uploadBytes(teamId: teamId, surveyId: surveyId, filenameHint: result.files.first.name, bytes: bytes);
    await _afterUpload(id: id, surveyId: surveyId, questionId: questionId, storagePath: storagePath, type: 'photo');
  }

  Future<void> addPhotoFromGallery({
    required BuildContext context,
    required String teamId,
    required String surveyId,
    required String questionId,
  }) async {
    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final id = _uuid.v4();
      await _db.addLocalAttachment(id: id, surveyId: surveyId, questionId: questionId, type: 'photo', localPath: file.name);
      final storagePath = await _uploadBytes(teamId: teamId, surveyId: surveyId, filenameHint: file.name, bytes: file.bytes!);
      await _afterUpload(id: id, surveyId: surveyId, questionId: questionId, storagePath: storagePath, type: 'photo');
      return;
    }
    if (Platform.isIOS || Platform.isAndroid) {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final id = _uuid.v4();
      await _db.addLocalAttachment(id: id, surveyId: surveyId, questionId: questionId, type: 'photo', localPath: picked.path);
      final bytes = await picked.readAsBytes();
      final storagePath = await _uploadBytes(teamId: teamId, surveyId: surveyId, filenameHint: picked.name, bytes: bytes);
      await _afterUpload(id: id, surveyId: surveyId, questionId: questionId, storagePath: storagePath, type: 'photo');
      return;
    }
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;
    final localPath = result.files.first.path!;
    final id = _uuid.v4();
    await _db.addLocalAttachment(id: id, surveyId: surveyId, questionId: questionId, type: 'photo', localPath: localPath);
    final bytes = await File(localPath).readAsBytes();
    final storagePath = await _uploadBytes(teamId: teamId, surveyId: surveyId, filenameHint: result.files.first.name, bytes: bytes);
    await _afterUpload(id: id, surveyId: surveyId, questionId: questionId, storagePath: storagePath, type: 'photo');
  }

  Future<String> _uploadBytes({
    required String teamId,
    required String surveyId,
    required String filenameHint,
    required Uint8List bytes,
  }) async {
    final ext = filenameHint.split('.').last.toLowerCase();
    final path = '${teamId}/${surveyId}/${_uuid.v4()}.$ext';
    await _client.storage.from('attachments').uploadBinary(path, bytes, fileOptions: const FileOptions(cacheControl: '3600', upsert: false));
    return path;
  }

  Future<void> _afterUpload({required String id, required String surveyId, required String questionId, required String storagePath, required String type}) async {
    await _db.setAttachmentStoragePath(id: id, storagePath: storagePath);
    try {
      await _client.from('attachments').insert({
        'id': id,
        'survey_id': surveyId,
        'question_id': questionId,
        'type': type,
        'storage_path': storagePath,
      });
    } catch (_) {
      // ignore and rely on sync later if needed
    }
  }

  Future<void> addSketch({
    required BuildContext context,
    required String teamId,
    required String surveyId,
    required String questionId,
    Uint8List? backgroundBytes,
  }) async {
    final resultBytes = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(
        builder: (_) => SketchPage(background: backgroundBytes),
      ),
    );
    if (resultBytes == null) return;
    final id = _uuid.v4();
    await _db.addLocalAttachment(id: id, surveyId: surveyId, questionId: questionId, type: 'sketch', localPath: 'sketch.png');
    final storagePath = await _uploadBytes(teamId: teamId, surveyId: surveyId, filenameHint: 'sketch.png', bytes: resultBytes);
    await _afterUpload(id: id, surveyId: surveyId, questionId: questionId, storagePath: storagePath, type: 'sketch');
  }

  Future<void> addSketchOverPhotoFromGallery({
    required BuildContext context,
    required String teamId,
    required String surveyId,
    required String questionId,
  }) async {
    Uint8List? bgBytes;
    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.isEmpty) return;
      bgBytes = result.files.first.bytes;
    } else if (Platform.isIOS || Platform.isAndroid) {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      bgBytes = await picked.readAsBytes();
    } else {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.isEmpty) return;
      bgBytes = await File(result.files.first.path!).readAsBytes();
    }
    await addSketch(context: context, teamId: teamId, surveyId: surveyId, questionId: questionId, backgroundBytes: bgBytes);
  }
}
