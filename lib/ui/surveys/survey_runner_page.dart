import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as d;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../models/template_schema.dart';
import '../../services/pdf_service.dart';
import '../../data/session_providers.dart';
import '../../services/attachments_service.dart';

class SurveyRunnerLauncher extends ConsumerStatefulWidget {
  const SurveyRunnerLauncher({super.key, required this.template});
  final Template template;

  @override
  ConsumerState<SurveyRunnerLauncher> createState() => _SurveyRunnerLauncherState();
}

class _SurveyRunnerLauncherState extends ConsumerState<SurveyRunnerLauncher> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final repo = ref.read(surveyRepositoryProvider);
    final team = ref.read(selectedTeamProvider);
    final session = Supabase.instance.client.auth.currentSession;
    final id = await repo.startSurvey(
      template: widget.template,
      teamId: team?.id,
      assigneeUserId: session?.user.id,
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SurveyRunnerPage(surveyId: id, templateId: widget.template.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class SurveyRunnerPage extends ConsumerStatefulWidget {
  const SurveyRunnerPage({super.key, required this.surveyId, required this.templateId});
  final String surveyId;
  final String templateId;

  @override
  ConsumerState<SurveyRunnerPage> createState() => _SurveyRunnerPageState();
}

class _SurveyRunnerPageState extends ConsumerState<SurveyRunnerPage> {
  TemplateSchema? _schema;
  final Map<String, dynamic> _answers = {}; // questionId -> value
  bool _loading = true;
  late final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _sectionKeys = [];
  List<bool> _expanded = const [];
  final Map<String, TextEditingController> _actionCtrls = {};
  final Set<String> _openActionEditors = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final tRow = await (db.select(db.templates)..where((t) => t.id.equals(widget.templateId))).getSingle();
    final schema = TemplateSchema.decode(tRow.schemaJson);
    // Load existing responses (if any)
    final existing = await (db.select(db.responses)..where((r) => r.surveyId.equals(widget.surveyId))).get();
    for (final r in existing) {
      _answers[r.questionId] = jsonDecode(r.valueJson);
    }
    setState(() {
      _schema = schema;
      _loading = false;
      _expanded = List<bool>.generate(schema.sections.length, (i) => i == 0);
      _sectionKeys.clear();
      _sectionKeys.addAll(List.generate(schema.sections.length, (_) => GlobalKey()));
    });
  }

  Future<void> _save() async {
    final repo = ref.read(surveyRepositoryProvider);
    // Validate required
    final missing = <String>[];
    for (final section in _schema!.sections) {
      if (!_isSectionVisible(section)) continue;
      for (final q in section.items) {
        if (!_isQuestionVisible(q)) continue;
        if (q.required) {
          final v = _answers[q.id];
          final isMissing = v == null || (v is String && v.trim().isEmpty);
          if (isMissing) missing.add(q.label);
        }
      }
    }
    if (missing.isNotEmpty) {
      final msg = 'Missing required: ${missing.join(', ')}';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
      return;
    }
    // Persist answers
    for (final entry in _answers.entries) {
      await repo.saveResponse(
        surveyId: widget.surveyId,
        questionId: entry.key,
        value: entry.value,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  Future<void> _exportPdf() async {
    if (_schema == null) return;
    final items = <Map<String, dynamic>>[];
    final actions = <Map<String, String>>[];
    final db = ref.read(databaseProvider);
    final client = Supabase.instance.client;

    for (final section in _schema!.sections) {
      for (final q in section.items) {
        final v = _answers[q.id];
        final note = _answers['note:${q.id}'] as String?;
        final action = _answers['action:${q.id}'] as String?;

        // Collect images for this question
        final atts = await (db.select(db.attachments)
              ..where((a) => a.surveyId.equals(widget.surveyId) & a.questionId.equals(q.id)))
            .get();
        final imgs = <Uint8List>[];
        for (final a in atts) {
          try {
            if (a.storagePath != null && a.storagePath!.isNotEmpty) {
              final bytes = await client.storage.from('attachments').download(a.storagePath!);
              imgs.add(bytes);
            }
          } catch (_) {
            // ignore failed downloads
          }
        }

        items.add({
          'question': q.label,
          'answer': _displayValue(q, v),
          if (note != null && note.isNotEmpty) 'note': note,
          'images': imgs,
        });
        if (action != null && action.isNotEmpty) {
          actions.add({'question': q.label, 'action': action});
        }
      }
    }
    await PdfService.shareSurveyPdfRich(title: _schema!.name, items: items, actions: actions);
  }

  Future<void> _openMediaSheet({required String questionId}) async {
    final team = ref.read(selectedTeamProvider);
    if (team == null) return;
    final db = ref.read(databaseProvider);
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Wrap(
              runSpacing: 8,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Camera'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await AttachmentsService(db, Supabase.instance.client)
                        .addPhoto(context: context, teamId: team.id, surveyId: widget.surveyId, questionId: questionId);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Gallery'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await AttachmentsService(db, Supabase.instance.client)
                        .addPhotoFromGallery(context: context, teamId: team.id, surveyId: widget.surveyId, questionId: questionId);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.brush),
                  title: const Text('Sketch'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await AttachmentsService(db, Supabase.instance.client)
                        .addSketch(context: context, teamId: team.id, surveyId: widget.surveyId, questionId: questionId);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Sketch over photo'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await AttachmentsService(db, Supabase.instance.client)
                        .addSketchOverPhotoFromGallery(context: context, teamId: team.id, surveyId: widget.surveyId, questionId: questionId);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add_a_photo),
                  title: const Text('Sketch over camera'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await AttachmentsService(db, Supabase.instance.client)
                        .addSketchOverCamera(context: context, teamId: team.id, surveyId: widget.surveyId, questionId: questionId);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.draw),
                  title: const Text('Signature'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await AttachmentsService(db, Supabase.instance.client)
                        .addSignature(context: context, teamId: team.id, surveyId: widget.surveyId, questionId: questionId);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  TextEditingController _getActionCtrl(String qid) {
    return _actionCtrls.putIfAbsent(qid, () {
      final initial = (_answers['action:$qid'] as String?) ?? '';
      return TextEditingController(text: initial);
    });
  }

  String _displayValue(QuestionItem q, dynamic v) {
    if (v == null) return '-';
    switch (q.type) {
      case QuestionType.text:
        return v.toString();
      case QuestionType.yesNoNa:
        return v.toString();
      case QuestionType.singleChoice:
        return v.toString();
      case QuestionType.multiChoice:
        return (v as List).join(', ');
      case QuestionType.dropdown:
        return v.toString();
      case QuestionType.likert5:
        return v.toString();
      case QuestionType.dateTime:
        try {
          final d = v is String ? DateTime.parse(v) : (v as DateTime);
          return d.toLocal().toString();
        } catch (_) {
          return v.toString();
        }
      case QuestionType.number:
        return v.toString();
      case QuestionType.checkbox:
        return (v == true) ? 'Yes' : 'No';
      case QuestionType.media:
        return '(media)';
      case QuestionType.slider:
        return v.toString();
      case QuestionType.annotation:
        return '(annotation)';
      case QuestionType.signature:
        return '(signature)';
      case QuestionType.sketch:
        return '(sketch)';
      case QuestionType.location:
        return v.toString();
      case QuestionType.person:
        return v.toString();
      case QuestionType.instruction:
        return '';
    }
  }

  bool _evalCondition(VisibleCondition c) {
    final ans = _answers[c.questionId];
    final op = c.op;
    final val = c.value.trim();
    if (ans == null) return false;
    if (ans is List) {
      final contains = ans.map((e) => e.toString()).contains(val);
      if (op == 'contains') return contains;
      if (op == 'equals') return contains; // equals any in list
      if (op == 'notEquals') return !contains;
      return contains;
    }
    final a = ans.toString().trim();
    switch (op) {
      case 'equals':
        return a == val;
      case 'notEquals':
        return a != val;
      case 'contains':
        return a.contains(val);
      default:
        return a == val;
    }
  }

  bool _isQuestionVisible(QuestionItem q) {
    final conds = q.visibleIf ?? const [];
    if (conds.isEmpty) return true;
    for (final c in conds) {
      if (!_evalCondition(c)) return false;
    }
    return true;
  }

  bool _isSectionVisible(TemplateSection s) {
    final conds = s.visibleIf ?? const [];
    if (conds.isEmpty) return true;
    for (final c in conds) {
      if (!_evalCondition(c)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _schema == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final sections = _schema!.sections;
    return Scaffold(
      appBar: AppBar(
        title: Text(_schema!.name),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.save)),
          IconButton(onPressed: _exportPdf, icon: const Icon(Icons.picture_as_pdf)),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          if (_schema!.brandName != null || _schema!.brandLogoUrl != null || _schema!.brandLogoStoragePath != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  if (_schema!.brandLogoUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Image.network(_schema!.brandLogoUrl!, width: 40, height: 40, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    ),
                  if (_schema!.brandLogoStoragePath != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FutureBuilder<String>(
                        future: Supabase.instance.client.storage
                            .from('branding')
                            .createSignedUrl(_schema!.brandLogoStoragePath!, 3600)
                            .then((r) => r as String),
                        builder: (context, snap) {
                          if (!snap.hasData) return const SizedBox(width: 40, height: 40);
                          return Image.network(snap.data!, width: 40, height: 40, errorBuilder: (_, __, ___) => const SizedBox.shrink());
                        },
                      ),
                    ),
                  if (_schema!.brandName != null)
                    Text(_schema!.brandName!, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(sections.length, (i) => i)
                  .where((i) => _isSectionVisible(sections[i]))
                  .map((i) {
                final s = sections[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(s.title),
                    selected: _expanded[i],
                    onSelected: (_) async {
                      setState(() {
                        for (int j = 0; j < _expanded.length; j++) _expanded[j] = (j == i);
                      });
                      await Future.delayed(const Duration(milliseconds: 100));
                      final ctx = _sectionKeys[i].currentContext;
                      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250));
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(sections.length, (i) => i)
              .where((i) => _isSectionVisible(sections[i]))
              .map((i) {
            final s = sections[i];
            return Container(
              key: _sectionKeys[i],
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                initiallyExpanded: _expanded[i],
                title: Text(s.title, style: Theme.of(context).textTheme.titleLarge),
                onExpansionChanged: (v) => setState(() => _expanded[i] = v),
                children: [
                  const SizedBox(height: 8),
                  ...s.items.where(_isQuestionVisible).map((q) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _QuestionAnswerWidget(
                            key: ValueKey(q.id),
                            item: q,
                            value: _answers[q.id],
                            onChanged: (val) => setState(() => _answers[q.id] = val),
                          ),
                          // Inline actions (Note / Media / Action)
                          Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () async {
                                    // Toggle inline note editor below action row
                                    final key = 'note:${q.id}';
                                    final current = (_answers[key] as String?) ?? '';
                                    final ctrl = TextEditingController(text: current);
                                    final result = await showModalBottomSheet<String>(
                                      context: context,
                                      builder: (ctx) => SafeArea(
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TextField(
                                                controller: ctrl,
                                                minLines: 3,
                                                maxLines: null,
                                                decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
                                                textCapitalization: TextCapitalization.sentences,
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                children: [
                                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                                  ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
                                                ],
                                              )
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                    if (result != null) {
                                      setState(() => _answers[key] = result);
                                    }
                                  },
                                  icon: const Icon(Icons.note_add_outlined),
                                  label: const Text('Note'),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () => _openMediaSheet(questionId: q.id),
                                  icon: const Icon(Icons.perm_media_outlined),
                                  label: const Text('Media'),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () {
                                    final qid = q.id;
                                    setState(() {
                                      if (_openActionEditors.contains(qid)) {
                                        _openActionEditors.remove(qid);
                                      } else {
                                        _openActionEditors.add(qid);
                                      }
                                    });
                                  },
                                  icon: const Icon(Icons.task_alt_outlined),
                                  label: const Text('Action'),
                                ),
                              ],
                            ),
                          ),
                          if (_openActionEditors.contains(q.id) || ((_answers['action:${q.id}'] as String?)?.isNotEmpty == true))
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0, bottom: 4.0),
                              child: TextField(
                                controller: _getActionCtrl(q.id),
                                minLines: 2,
                                maxLines: null,
                                decoration: const InputDecoration(hintText: 'Describe follow-up action', border: OutlineInputBorder()),
                                textCapitalization: TextCapitalization.sentences,
                                onChanged: (v) => _answers['action:${q.id}'] = v,
                              ),
                            ),
                          // Show attachments list below actions
                          Padding(
                            padding: const EdgeInsets.only(left: 4.0, top: 6.0, bottom: 12.0),
                            child: _AttachmentsBlock(surveyId: widget.surveyId, questionId: q.id),
                          ),
                        ],
                      )),
                  const SizedBox(height: 8),
                ],
              ),
            );
          }),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Submit'),
          ),
        ),
      ),
    );
  }
}

class _QuestionAnswerWidget extends StatelessWidget {
  const _QuestionAnswerWidget({super.key, required this.item, required this.value, required this.onChanged});
  final QuestionItem item;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    switch (item.type) {
      case QuestionType.text:
        return _TextAnswer(item: item, value: value?.toString() ?? '', onChanged: onChanged);
      case QuestionType.yesNoNa:
        return _YesNoNaAnswer(item: item, value: value?.toString(), onChanged: onChanged);
      case QuestionType.singleChoice:
        return _SingleChoiceAnswer(item: item, value: value?.toString(), onChanged: onChanged);
      case QuestionType.multiChoice:
        return _MultiChoiceAnswer(item: item, values: (value as List?)?.cast<String>() ?? const [], onChanged: onChanged);
      case QuestionType.dropdown:
        return _DropdownAnswer(item: item, value: value?.toString(), onChanged: onChanged);
      case QuestionType.likert5:
        return _Likert5Answer(item: item, value: (value as int?) ?? 0, onChanged: onChanged);
      case QuestionType.dateTime:
        return _DateTimeAnswer(item: item, value: value, onChanged: onChanged);
      case QuestionType.number:
        return _NumberAnswer(item: item, value: (value is num) ? value : null, onChanged: onChanged);
      case QuestionType.checkbox:
        return _CheckboxAnswer(item: item, value: value == true, onChanged: onChanged);
      case QuestionType.media:
        return _MediaAnswer(item: item, surveyId: (context.findAncestorWidgetOfExactType<SurveyRunnerPage>()!).surveyId);
      case QuestionType.slider:
        return _SliderAnswer(item: item, value: (value as num?)?.toDouble() ?? 0.0, onChanged: onChanged);
      case QuestionType.annotation:
        return _AnnotationAnswer(item: item);
      case QuestionType.signature:
        return _SignatureAnswer(item: item);
      case QuestionType.sketch:
        return _SketchOnlyAnswer(item: item);
      case QuestionType.location:
        return _TextAnswer(item: item, value: value?.toString() ?? '', onChanged: onChanged);
      case QuestionType.person:
        return _PersonAnswer(item: item, value: value?.toString(), onChanged: onChanged);
      case QuestionType.instruction:
        return _Instruction(item: item);
    }
  }
}

class _NumberAnswer extends StatefulWidget {
  const _NumberAnswer({required this.item, required this.value, required this.onChanged});
  final QuestionItem item;
  final num? value;
  final ValueChanged<num?> onChanged;
  @override
  State<_NumberAnswer> createState() => _NumberAnswerState();
}

class _NumberAnswerState extends State<_NumberAnswer> {
  late TextEditingController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant _NumberAnswer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newText = widget.value?.toString() ?? '';
    if (_ctrl.text != newText) {
      _ctrl.text = newText;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: _ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: widget.item.label + (widget.item.required ? ' *' : ''), border: const OutlineInputBorder()),
        onChanged: (v) => widget.onChanged(num.tryParse(v)),
      ),
    );
  }
}

class _CheckboxAnswer extends StatelessWidget {
  const _CheckboxAnswer({required this.item, required this.value, required this.onChanged});
  final QuestionItem item;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(item.label + (item.required ? ' *' : '')),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _SliderAnswer extends StatelessWidget {
  const _SliderAnswer({required this.item, required this.value, required this.onChanged});
  final QuestionItem item;
  final double value;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) {
    double min = 0, max = 10;
    final opts = item.options ?? const [];
    if (opts.length >= 2) {
      final a = double.tryParse(opts[0]);
      final b = double.tryParse(opts[1]);
      if (a != null && b != null) {
        min = a; max = b;
      }
    }
    final v = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.label + (item.required ? ' *' : '')),
          Slider(
            value: v,
            min: min,
            max: max,
            divisions: (max - min).toInt() > 0 ? (max - min).toInt() : null,
            label: v.toStringAsFixed(0),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _Instruction extends StatelessWidget {
  const _Instruction({required this.item});
  final QuestionItem item;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(item.label, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}

class _PersonAnswer extends ConsumerStatefulWidget {
  const _PersonAnswer({required this.item, required this.value, required this.onChanged});
  final QuestionItem item;
  final String? value;
  final ValueChanged<String> onChanged;
  @override
  ConsumerState<_PersonAnswer> createState() => _PersonAnswerState();
}

class _PersonAnswerState extends ConsumerState<_PersonAnswer> {
  late TextEditingController _ctrl;
  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    final initial = widget.value ?? client.auth.currentUser?.userMetadata?['full_name'] as String? ?? client.auth.currentUser?.email ?? '';
    _ctrl = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fullName = ref.watch(currentUserFullNameProvider);
    fullName.whenData((name) {
      if ((name != null && name.isNotEmpty) && _ctrl.text.trim().isEmpty) {
        _ctrl.text = name;
        widget.onChanged(name);
      }
    });
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: _ctrl,
        decoration: InputDecoration(
          labelText: widget.item.label.isEmpty ? 'Person' : widget.item.label,
          border: const OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.words,
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _MediaAnswer extends ConsumerWidget {
  const _MediaAnswer({required this.item, required this.surveyId});
  final QuestionItem item;
  final String surveyId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(selectedTeamProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.label + (item.required ? ' *' : '')),
        const SizedBox(height: 8),
        _AttachmentsBlock(surveyId: surveyId, questionId: item.id),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: team == null ? null : () => (context.findAncestorStateOfType<_SurveyRunnerPageState>())?._openMediaSheet(questionId: item.id),
            icon: const Icon(Icons.perm_media_outlined),
            label: const Text('Add media'),
          ),
        ),
      ],
    );
  }
}

class _AnnotationAnswer extends ConsumerWidget {
  const _AnnotationAnswer({required this.item});
  final QuestionItem item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(selectedTeamProvider);
    final surveyId = (context.findAncestorWidgetOfExactType<SurveyRunnerPage>()!).surveyId;
    return Wrap(
      spacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed: team == null ? null : () async {
            final db = ref.read(databaseProvider);
            await AttachmentsService(db, Supabase.instance.client).addSketchOverPhotoFromGallery(context: context, teamId: team.id, surveyId: surveyId, questionId: item.id);
          },
          icon: const Icon(Icons.edit),
          label: Text(item.label.isEmpty ? 'Sketch over photo' : item.label),
        ),
      ],
    );
  }
}

class _SignatureAnswer extends ConsumerWidget {
  const _SignatureAnswer({required this.item});
  final QuestionItem item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(selectedTeamProvider);
    final surveyId = (context.findAncestorWidgetOfExactType<SurveyRunnerPage>()!).surveyId;
    return ElevatedButton.icon(
      onPressed: team == null ? null : () async {
        final db = ref.read(databaseProvider);
        await AttachmentsService(db, Supabase.instance.client).addSignature(context: context, teamId: team.id, surveyId: surveyId, questionId: item.id);
      },
      icon: const Icon(Icons.draw),
      label: Text(item.label.isEmpty ? 'Add signature' : item.label),
    );
  }
}

class _SketchOnlyAnswer extends ConsumerWidget {
  const _SketchOnlyAnswer({required this.item});
  final QuestionItem item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(selectedTeamProvider);
    final surveyId = (context.findAncestorWidgetOfExactType<SurveyRunnerPage>()!).surveyId;
    return ElevatedButton.icon(
      onPressed: team == null ? null : () async {
        final db = ref.read(databaseProvider);
        await AttachmentsService(db, Supabase.instance.client).addSketch(context: context, teamId: team.id, surveyId: surveyId, questionId: item.id);
      },
      icon: const Icon(Icons.brush),
      label: Text(item.label.isEmpty ? 'Add sketch' : item.label),
    );
  }
}

class _DateTimeAnswer extends StatefulWidget {
  const _DateTimeAnswer({required this.item, required this.value, required this.onChanged});
  final QuestionItem item;
  final dynamic value; // String iso8601 or null
  final ValueChanged<dynamic> onChanged;

  @override
  State<_DateTimeAnswer> createState() => _DateTimeAnswerState();
}

class _DateTimeAnswerState extends State<_DateTimeAnswer> {
  DateTime? _value;

  @override
  void initState() {
    super.initState();
    final v = widget.value;
    if (v is String) {
      try { _value = DateTime.parse(v); } catch (_) {}
    } else if (v is DateTime) {
      _value = v;
    }
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 5), initialDate: _value ?? now);
    if (d == null) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_value ?? now));
    if (t == null) return;
    final dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() => _value = dt);
    widget.onChanged(dt.toIso8601String());
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.item.label + (widget.item.required ? ' *' : '');
    final text = _value != null ? _value!.toLocal().toString() : 'Tap to pick date/time';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        onTap: _pick,
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          child: Text(text),
        ),
      ),
    );
  }
}

class _TextAnswer extends StatefulWidget {
  const _TextAnswer({required this.item, required this.value, required this.onChanged});
  final QuestionItem item;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_TextAnswer> createState() => _TextAnswerState();
}

class _TextAnswerState extends State<_TextAnswer> {
  late TextEditingController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: _ctrl,
        decoration: InputDecoration(
          labelText: widget.item.label + (widget.item.required ? ' *' : ''),
          border: const OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.sentences,
        keyboardType: widget.item.type == QuestionType.text && widget.item.multiLine
            ? TextInputType.multiline
            : TextInputType.text,
        minLines: widget.item.type == QuestionType.text && widget.item.multiLine ? 3 : 1,
        maxLines: widget.item.type == QuestionType.text && widget.item.multiLine ? null : 1,
        textInputAction: widget.item.type == QuestionType.text && widget.item.multiLine
            ? TextInputAction.newline
            : TextInputAction.done,
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _YesNoNaAnswer extends StatelessWidget {
  const _YesNoNaAnswer({required this.item, required this.value, required this.onChanged});
  final QuestionItem item;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.label + (item.required ? ' *' : '')),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Yes'),
                selected: value == 'yes',
                onSelected: (_) => onChanged('yes'),
              ),
              ChoiceChip(
                label: const Text('No'),
                selected: value == 'no',
                onSelected: (_) => onChanged('no'),
              ),
              ChoiceChip(
                label: const Text('N/A'),
                selected: value == 'na',
                onSelected: (_) => onChanged('na'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SingleChoiceAnswer extends StatelessWidget {
  const _SingleChoiceAnswer({required this.item, required this.value, required this.onChanged});
  final QuestionItem item;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final opts = item.options ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.label + (item.required ? ' *' : '')),
          ...opts.map((o) => RadioListTile<String>(
                value: o,
                groupValue: value,
                onChanged: (v) => onChanged(v ?? ''),
                title: Text(o),
              )),
        ],
      ),
    );
  }
}

class _MultiChoiceAnswer extends StatefulWidget {
  const _MultiChoiceAnswer({required this.item, required this.values, required this.onChanged});
  final QuestionItem item;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_MultiChoiceAnswer> createState() => _MultiChoiceAnswerState();
}

class _MultiChoiceAnswerState extends State<_MultiChoiceAnswer> {
  late List<String> _values;
  @override
  void initState() {
    super.initState();
    _values = List.of(widget.values);
  }

  @override
  Widget build(BuildContext context) {
    final opts = widget.item.options ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.item.label + (widget.item.required ? ' *' : '')),
          ...opts.map((o) {
            final selected = _values.contains(o);
            return CheckboxListTile(
              value: selected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _values.add(o);
                  } else {
                    _values.remove(o);
                  }
                });
                widget.onChanged(List.of(_values));
              },
              title: Text(o),
              controlAffinity: ListTileControlAffinity.leading,
            );
          }),
        ],
      ),
    );
  }
}

class _DropdownAnswer extends StatelessWidget {
  const _DropdownAnswer({required this.item, required this.value, required this.onChanged});
  final QuestionItem item;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final opts = item.options ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<String>(
        value: value?.isNotEmpty == true ? value : null,
        decoration: InputDecoration(
          labelText: item.label + (item.required ? ' *' : ''),
          border: const OutlineInputBorder(),
        ),
        items: opts.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
        onChanged: (v) => onChanged(v ?? ''),
      ),
    );
  }
}

class _Likert5Answer extends StatelessWidget {
  const _Likert5Answer({required this.item, required this.value, required this.onChanged});
  final QuestionItem item;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = const ['1', '2', '3', '4', '5'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.label + (item.required ? ' *' : '')),
          Wrap(
            spacing: 8,
            children: List.generate(5, (i) {
              final selected = value == i + 1;
              return ChoiceChip(
                label: Text(labels[i]),
                selected: selected,
                onSelected: (_) => onChanged(i + 1),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _AttachmentsBlock extends ConsumerWidget {
  const _AttachmentsBlock({super.key, required this.surveyId, required this.questionId});
  final String surveyId;
  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final team = ref.watch(selectedTeamProvider);
    final stream = db.watchAttachmentsFor(surveyId, questionId);
    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((a) => Chip(label: Text(a.storagePath ?? a.localPath ?? 'attachment'))).toList(),
        );
      },
    );
  }
}
