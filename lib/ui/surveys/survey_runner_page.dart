import 'dart:convert';

import 'package:flutter/material.dart';
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
    });
  }

  Future<void> _save() async {
    final repo = ref.read(surveyRepositoryProvider);
    // Validate required
    final missing = <String>[];
    for (final section in _schema!.sections) {
      for (final q in section.items) {
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
    final qa = <Map<String, String>>[];
    for (final section in _schema!.sections) {
      for (final q in section.items) {
        final v = _answers[q.id];
        qa.add({'question': q.label, 'answer': _displayValue(q, v)});
      }
    }
    await PdfService.shareSurveyPdf(title: _schema!.name, qaPairs: qa);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _schema == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final section = _schema!.sections.first;
    return Scaffold(
      appBar: AppBar(
        title: Text(_schema!.name),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.save)),
          IconButton(onPressed: _exportPdf, icon: const Icon(Icons.picture_as_pdf)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(section.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...section.items.map((q) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _QuestionAnswerWidget(
                    key: ValueKey(q.id),
                    item: q,
                    value: _answers[q.id],
                    onChanged: (val) => setState(() => _answers[q.id] = val),
                  ),
                  if (q.allowAttachment)
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0, top: 6.0, bottom: 12.0),
                      child: _AttachmentsBlock(surveyId: widget.surveyId, questionId: q.id),
                    ),
                ],
              )),
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
    }
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items.map((a) => Chip(label: Text(a.storagePath ?? a.localPath ?? 'attachment'))).toList(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: team == null
                      ? null
                      : () async {
                          final svc = AttachmentsService(db, Supabase.instance.client);
                          await svc.addPhoto(context: context, teamId: team.id, surveyId: surveyId, questionId: questionId);
                        },
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Camera'),
                ),
                ElevatedButton.icon(
                  onPressed: team == null
                      ? null
                      : () async {
                          final svc = AttachmentsService(db, Supabase.instance.client);
                          await svc.addPhotoFromGallery(context: context, teamId: team.id, surveyId: surveyId, questionId: questionId);
                        },
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
                ElevatedButton.icon(
                  onPressed: team == null
                      ? null
                      : () async {
                          final svc = AttachmentsService(db, Supabase.instance.client);
                          await svc.addSketch(context: context, teamId: team.id, surveyId: surveyId, questionId: questionId);
                        },
                  icon: const Icon(Icons.brush),
                  label: const Text('Sketch'),
                ),
                ElevatedButton.icon(
                  onPressed: team == null
                      ? null
                      : () async {
                          final svc = AttachmentsService(db, Supabase.instance.client);
                          await svc.addSketchOverPhotoFromGallery(context: context, teamId: team.id, surveyId: surveyId, questionId: questionId);
                        },
                  icon: const Icon(Icons.edit),
                  label: const Text('Sketch over photo'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
