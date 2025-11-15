import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';

import '../../data/repositories.dart';
import '../../data/session_providers.dart';
import '../../services/sync_service.dart';
import '../../services/attachments_service.dart';
import '../../data/providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/template_schema.dart';
import 'reorder_questions_page.dart';

class TemplateBuilderPage extends ConsumerStatefulWidget {
  const TemplateBuilderPage({super.key, required this.initialSchema});
  final TemplateSchema initialSchema;

  @override
  ConsumerState<TemplateBuilderPage> createState() => _TemplateBuilderPageState();
}

class _TemplateBuilderPageState extends ConsumerState<TemplateBuilderPage> {
  late TextEditingController _nameCtrl;
  late TextEditingController _brandCtrl;
  late TextEditingController _logoCtrl;
  late TextEditingController _logoStorageCtrl;
  late TemplateSchema _schema;
  final _uuid = const Uuid();
  int _currentSectionIndex = 0;
  final Map<String, TextEditingController> _sectionTitleCtrls = {};
  final Map<String, FocusNode> _sectionTitleFocus = {};

  @override
  void initState() {
    super.initState();
    _schema = widget.initialSchema;
    _nameCtrl = TextEditingController(text: _schema.name);
    _brandCtrl = TextEditingController(text: _schema.brandName ?? '');
    _logoCtrl = TextEditingController(text: _schema.brandLogoUrl ?? '');
    _logoStorageCtrl = TextEditingController(text: _schema.brandLogoStoragePath ?? '');
    _initPublished();
    // Ensure controllers for each existing section
    for (final s in _schema.sections) {
      _sectionTitleCtrls[s.id] = TextEditingController(text: s.title);
      final fn = FocusNode();
      fn.addListener(() {
        if (fn.hasFocus) {
          final ctrl = _sectionTitleCtrls[s.id]!;
          if (ctrl.text.trim().toLowerCase() == 'new section') {
            ctrl.clear();
          }
        }
      });
      _sectionTitleFocus[s.id] = fn;
    }
  }

  Future<void> _initPublished() async {
    if (_schema.id.isEmpty) return;
    final db = ref.read(databaseProvider);
    final row = await (db.select(db.templates)..where((t) => t.id.equals(_schema.id))).getSingleOrNull();
    if (row != null && mounted) setState(() => _published = row.published);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _logoCtrl.dispose();
    _logoStorageCtrl.dispose();
    for (final c in _sectionTitleCtrls.values) {
      c.dispose();
    }
    for (final f in _sectionTitleFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _addQuestion() {
    final section = _schema.sections[_currentSectionIndex];
    final newItem = QuestionItem(
      id: _uuid.v4(),
      type: QuestionType.text,
      label: 'New question',
      required: false,
      allowAttachment: false,
    );
    setState(() {
      section.items.add(newItem);
    });
  }

  Future<void> _saveTemplate() async {
    final repo = ref.read(templateRepositoryProvider);
    final team = ref.read(selectedTeamProvider);
    final updated = TemplateSchema(
      id: _schema.id.isEmpty ? _uuid.v4() : _schema.id,
      name: _nameCtrl.text.trim().isEmpty ? 'Untitled Template' : _nameCtrl.text.trim(),
      version: _schema.version,
      sections: _schema.sections,
      brandName: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
      brandLogoUrl: _logoCtrl.text.trim().isEmpty ? null : _logoCtrl.text.trim(),
      brandLogoStoragePath: _logoStorageCtrl.text.trim().isEmpty ? null : _logoStorageCtrl.text.trim(),
    );
    final published = _published;
    await repo.createOrUpdateTemplate(updated, teamId: published ? null : team?.id, published: published);
    // Push immediately so it's available after reinstall
    await ref.read(syncServiceProvider).pushPendingOps();
    if (mounted) Navigator.pop(context);
  }

  bool _published = false;

  void _addSection() {
    setState(() {
      final id = _uuid.v4();
      final section = TemplateSection(id: id, title: 'New Section', items: []);
      _schema.sections.add(section);
      _sectionTitleCtrls[id] = TextEditingController(text: section.title);
      final fn = FocusNode();
      fn.addListener(() {
        if (fn.hasFocus) {
          final ctrl = _sectionTitleCtrls[id]!;
          if (ctrl.text.trim().toLowerCase() == 'new section') {
            ctrl.clear();
          }
        }
      });
      _sectionTitleFocus[id] = fn;
      _currentSectionIndex = _schema.sections.length - 1;
    });
    // Focus newly added section title
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _schema.sections[_currentSectionIndex].id;
      _sectionTitleFocus[id]?.requestFocus();
    });
  }

  void _deleteCurrentSection() {
    if (_schema.sections.length <= 1) return;
    setState(() {
      final removed = _schema.sections.removeAt(_currentSectionIndex);
      _sectionTitleCtrls.remove(removed.id)?.dispose();
      if (_currentSectionIndex >= _schema.sections.length) {
        _currentSectionIndex = _schema.sections.length - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final section = _schema.sections[_currentSectionIndex];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Template Builder'),
        actions: [
          TextButton.icon(
            onPressed: _saveTemplate,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addQuestion,
        icon: const Icon(Icons.add),
        label: const Text('Add Question'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Template name',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _brandCtrl,
                decoration: const InputDecoration(labelText: 'Brand name (optional)', border: OutlineInputBorder()),
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _logoCtrl,
                decoration: const InputDecoration(labelText: 'Logo URL (optional)', border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _logoStorageCtrl,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Logo storage path (branding bucket)', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () async {
                final team = ref.read(selectedTeamProvider);
                if (team == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a team to upload logo')));
                  return;
                }
                final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
                if (res == null || res.files.isEmpty) return;
                final file = res.files.first;
                final svc = AttachmentsService(ref.read(databaseProvider), Supabase.instance.client);
                final path = await svc.uploadBrandLogoBytes(teamId: team.id, filenameHint: file.name, bytes: file.bytes!);
                final signed = await Supabase.instance.client.storage.from('branding').createSignedUrl(path, 60 * 60 * 24 * 365);
                setState(() {
                  _logoStorageCtrl.text = path;
                  _logoCtrl.text = signed as String;
                });
              },
              icon: const Icon(Icons.upload),
              label: const Text('Upload Logo'),
            ),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _published,
            onChanged: (v) => setState(() => _published = v),
            title: const Text('Publish to shared library (visible to all teams)'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              ...List.generate(_schema.sections.length, (i) {
                final s = _schema.sections[i];
                final selected = i == _currentSectionIndex;
                return ChoiceChip(
                  label: Text(s.title.isEmpty ? 'Section ${i + 1}' : s.title),
                  selected: selected,
                  onSelected: (_) => setState(() => _currentSectionIndex = i),
                );
              }),
              ActionChip(label: const Text('Add section'), avatar: const Icon(Icons.add), onPressed: _addSection),
              if (_schema.sections.length > 1)
                ActionChip(label: const Text('Delete section'), avatar: const Icon(Icons.delete_outline), onPressed: _deleteCurrentSection),
              ActionChip(
                label: const Text('Reorder questions'),
                avatar: const Icon(Icons.drag_handle),
                onPressed: () async {
                  final current = _schema.sections[_currentSectionIndex];
                  final result = await Navigator.push<List<QuestionItem>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReorderQuestionsPage(initial: current.items),
                    ),
                  );
                  if (result != null) {
                    setState(() {
                      _schema.sections[_currentSectionIndex] = TemplateSection(
                        id: current.id,
                        title: current.title,
                        description: current.description,
                        items: result,
                        visibleIf: current.visibleIf,
                      );
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(labelText: 'Section title', border: OutlineInputBorder()),
            controller: _sectionTitleCtrls[section.id],
            focusNode: _sectionTitleFocus[section.id],
            textCapitalization: TextCapitalization.sentences,
            onChanged: (v) => setState(() => _schema.sections[_currentSectionIndex] = TemplateSection(id: section.id, title: v, description: section.description, items: section.items)),
          ),
          const SizedBox(height: 8),
          if (section.description != null)
            Text(section.description!),
          // Section-level visibility conditions
          ExpansionTile(
            title: const Text('Section visibility (show when conditions are met)'),
            children: [
              ...((section.visibleIf ?? const <VisibleCondition>[])
                  .asMap()
                  .entries
                  .map((entry) {
                final i = entry.key;
                final cond = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Row(
                    children: [
                      DropdownButton<String>(
                        value: cond.op,
                        items: const [
                          DropdownMenuItem(value: 'equals', child: Text('equals')),
                          DropdownMenuItem(value: 'notEquals', child: Text('not equals')),
                          DropdownMenuItem(value: 'contains', child: Text('contains')),
                        ],
                        onChanged: (v) {
                          final list = List<VisibleCondition>.of(section.visibleIf ?? const <VisibleCondition>[]);
                          list[i] = VisibleCondition(questionId: cond.questionId, op: v ?? 'equals', value: cond.value);
                          setState(() => _schema.sections[_currentSectionIndex] = TemplateSection(
                                id: section.id,
                                title: section.title,
                                description: section.description,
                                items: section.items,
                                visibleIf: list,
                              ));
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Builder(builder: (context) {
                          final all = <MapEntry<String, String>>[];
                          for (final sec in _schema.sections) {
                            for (final qq in sec.items) {
                              final label = sec.title.isNotEmpty ? '${sec.title}: ${qq.label}' : qq.label;
                              all.add(MapEntry(qq.id, label));
                            }
                          }
                          return InputDecorator(
                            decoration: const InputDecoration(labelText: 'Question', border: OutlineInputBorder()),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                key: ValueKey('sec-cond-${section.id}-$i-q'),
                                isExpanded: true,
                                value: (section.visibleIf?[i].questionId.isNotEmpty ?? false)
                                    ? section.visibleIf![i].questionId
                                    : null,
                                items: all.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                                onChanged: (v) {
                                  final list = List<VisibleCondition>.of(section.visibleIf ?? const <VisibleCondition>[]);
                                  list[i] = VisibleCondition(questionId: v ?? '', op: cond.op, value: cond.value);
                                  setState(() => _schema.sections[_currentSectionIndex] = TemplateSection(
                                        id: section.id,
                                        title: section.title,
                                        description: section.description,
                                        items: section.items,
                                        visibleIf: list,
                                      ));
                                },
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('sec-cond-${section.id}-$i-val'),
                          initialValue: cond.value,
                          decoration: const InputDecoration(labelText: 'Value', border: OutlineInputBorder()),
                          onChanged: (v) {
                            final list = List<VisibleCondition>.of(section.visibleIf ?? const <VisibleCondition>[]);
                            list[i] = VisibleCondition(questionId: cond.questionId, op: cond.op, value: v);
                            setState(() => _schema.sections[_currentSectionIndex] = TemplateSection(
                                  id: section.id,
                                  title: section.title,
                                  description: section.description,
                                  items: section.items,
                                  visibleIf: list,
                                ));
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: () {
                          final list = List<VisibleCondition>.of(section.visibleIf ?? const <VisibleCondition>[]);
                          list.removeAt(i);
                          setState(() => _schema.sections[_currentSectionIndex] = TemplateSection(
                                id: section.id,
                                title: section.title,
                                description: section.description,
                                items: section.items,
                                visibleIf: list,
                              ));
                        },
                        icon: const Icon(Icons.delete_outline),
                      )
                    ],
                  ),
                );
              }).toList()),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    final list = List<VisibleCondition>.of(section.visibleIf ?? const <VisibleCondition>[]);
                    list.add(const VisibleCondition(questionId: '', op: 'equals', value: ''));
                    setState(() => _schema.sections[_currentSectionIndex] = TemplateSection(
                          id: section.id,
                          title: section.title,
                          description: section.description,
                          items: section.items,
                          visibleIf: list,
                        ));
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add condition'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final moved = section.items.removeAt(oldIndex);
                section.items.insert(newIndex, moved);
              });
            },
            children: [
              for (int i = 0; i < section.items.length; i++)
                KeyedSubtree(
                  key: ValueKey(section.items[i].id),
                  child: _QuestionEditor(
                    item: section.items[i],
                    reorderIndex: i,
                    // Build target list of prior questions only (all sections before + items before in current section)
                    targetQuestionOptions: () {
                      final opts = <MapEntry<String, String>>[];
                      for (final sec in _schema.sections) {
                        for (final qq in sec.items) {
                          final label = sec.title.isNotEmpty
                              ? '${sec.title}: ${qq.label}'
                              : qq.label;
                          opts.add(MapEntry(qq.id, label));
                        }
                      }
                      return opts;
                    }(),
                    onChanged: (updated) {
                      final idx = section.items.indexWhere((e) => e.id == updated.id);
                      setState(() {
                        section.items[idx] = updated;
                      });
                    },
                    onDelete: () {
                      setState(() {
                        section.items.removeAt(i);
                      });
                    },
                  ),
                ),
            ],
          ),
          if (section.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No questions yet. Tap "Add Question".'),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _QuestionEditor extends StatefulWidget {
  const _QuestionEditor({super.key, required this.item, required this.onChanged, required this.onDelete, this.reorderIndex, this.targetQuestionOptions = const []});
  final QuestionItem item;
  final ValueChanged<QuestionItem> onChanged;
  final VoidCallback onDelete;
  final int? reorderIndex;
  final List<MapEntry<String, String>> targetQuestionOptions;

  @override
  State<_QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<_QuestionEditor> {
  late TextEditingController _labelCtrl;
  late TextEditingController _optionsCtrl; // comma-separated for singleChoice
  late FocusNode _labelFocus;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.item.label);
    _optionsCtrl = TextEditingController(text: (widget.item.options ?? []).join(','));
    _labelFocus = FocusNode();
    _labelFocus.addListener(() {
      if (_labelFocus.hasFocus) {
        final txt = _labelCtrl.text.trim().toLowerCase();
        if (txt == 'new question') {
          // Clear placeholder on first focus so user can type immediately
          _labelCtrl.clear();
          _emitChanged(label: '');
        }
      }
    });
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _optionsCtrl.dispose();
    _labelFocus.dispose();
    super.dispose();
  }

  void _emitChanged({QuestionType? type, bool? requiredFlag, List<String>? options, String? label}) {
    widget.onChanged(QuestionItem(
      id: widget.item.id,
      type: type ?? widget.item.type,
      label: label ?? _labelCtrl.text,
      required: requiredFlag ?? widget.item.required,
      options: options ?? widget.item.options,
      allowAttachment: widget.item.allowAttachment,
      multiLine: widget.item.multiLine,
      visibleIf: widget.item.visibleIf,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
                Row(
                  children: [
                    const Text('Type:'),
                    const SizedBox(width: 8),
                    Flexible(
                      child: DropdownButton<QuestionType>(
                    value: widget.item.type,
                    onChanged: (v) => setState(() => _emitChanged(type: v)),
                    isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: QuestionType.text, child: Text('Text')),
                    DropdownMenuItem(value: QuestionType.yesNoNa, child: Text('Yes/No/N/A')),
                    DropdownMenuItem(value: QuestionType.singleChoice, child: Text('Single choice (radio)')),
                    DropdownMenuItem(value: QuestionType.multiChoice, child: Text('Multiple choice (checkboxes)')),
                    DropdownMenuItem(value: QuestionType.dropdown, child: Text('Dropdown')),
                    DropdownMenuItem(value: QuestionType.likert5, child: Text('Likert (1–5)')),
                    DropdownMenuItem(value: QuestionType.dateTime, child: Text('Date/Time')),
                    DropdownMenuItem(value: QuestionType.number, child: Text('Number')),
                    DropdownMenuItem(value: QuestionType.checkbox, child: Text('Checkbox')),
                    DropdownMenuItem(value: QuestionType.media, child: Text('Media')),
                    DropdownMenuItem(value: QuestionType.slider, child: Text('Slider')),
                    DropdownMenuItem(value: QuestionType.annotation, child: Text('Annotation (draw over photo)')),
                    DropdownMenuItem(value: QuestionType.signature, child: Text('Signature')),
                    DropdownMenuItem(value: QuestionType.sketch, child: Text('Sketch (blank canvas)')),
                    DropdownMenuItem(value: QuestionType.location, child: Text('Location (manual)')),
                    DropdownMenuItem(value: QuestionType.person, child: Text('Person (current user)')),
                    DropdownMenuItem(value: QuestionType.instruction, child: Text('Instruction (read only)')),
                  ],
                ),
              ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Required'),
                    Switch(
                      value: widget.item.required,
                      onChanged: (v) => setState(() => _emitChanged(requiredFlag: v)),
                    ),
                    const SizedBox(width: 6),
                    if (widget.reorderIndex != null)
                      ReorderableDragStartListener(
                        index: widget.reorderIndex!,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4.0),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                  ],
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              ],
            ),
            const SizedBox(height: 8),
          TextField(
            controller: _labelCtrl,
            focusNode: _labelFocus,
            decoration: const InputDecoration(
              labelText: 'Question label',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            onChanged: (v) => _emitChanged(label: v),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('ID: ${widget.item.id.substring(0, 8)}…', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Copy ID',
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () => Clipboard.setData(ClipboardData(text: widget.item.id)),
              ),
            ],
          ),
            if (widget.item.type == QuestionType.singleChoice ||
                widget.item.type == QuestionType.multiChoice ||
                widget.item.type == QuestionType.dropdown) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _optionsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Options (comma-separated)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final opts = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                  _emitChanged(options: opts);
                },
              ),
            ],
            if (widget.item.type == QuestionType.slider) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _optionsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Slider range (min,max)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final opts = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                  _emitChanged(options: opts);
                },
              ),
            ],
            if (widget.item.type == QuestionType.instruction) ...[
              const SizedBox(height: 8),
              const Text('Instruction text will be displayed as a read‑only block.'),
            ],
            if (widget.item.type == QuestionType.text) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Multiline'),
                  const SizedBox(width: 8),
                  Switch(
                    value: widget.item.multiLine,
                    onChanged: (v) {
                      widget.onChanged(QuestionItem(
                        id: widget.item.id,
                        type: widget.item.type,
                        label: _labelCtrl.text,
                        required: widget.item.required,
                        options: widget.item.options,
                        allowAttachment: widget.item.allowAttachment,
                        multiLine: v,
                      ));
                      setState(() {});
                    },
                  ),
                ],
              )
            ],
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text('Visibility (show when conditions are met)'),
              initiallyExpanded: false,
              children: [
                ...(widget.item.visibleIf ?? const [])
                    .asMap()
                    .entries
                    .map((entry) {
                  final i = entry.key;
                  final cond = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: Row(
                      children: [
                        DropdownButton<String>(
                          value: cond.op,
                          items: const [
                            DropdownMenuItem(value: 'equals', child: Text('equals')),
                            DropdownMenuItem(value: 'notEquals', child: Text('not equals')),
                            DropdownMenuItem(value: 'contains', child: Text('contains')),
                          ],
                          onChanged: (v) {
                            final list = List<VisibleCondition>.of(widget.item.visibleIf ?? const <VisibleCondition>[]);
                            list[i] = VisibleCondition(questionId: cond.questionId, op: v ?? 'equals', value: cond.value);
                            widget.onChanged(QuestionItem(
                              id: widget.item.id,
                              type: widget.item.type,
                              label: _labelCtrl.text,
                              required: widget.item.required,
                              options: widget.item.options,
                              allowAttachment: widget.item.allowAttachment,
                              multiLine: widget.item.multiLine,
                              visibleIf: list,
                            ));
                            setState(() {});
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Question', border: OutlineInputBorder()),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                key: ValueKey('ql-cond-${widget.item.id}-$i-q'),
                                isExpanded: true,
                                value: (widget.item.visibleIf?[i].questionId.isNotEmpty ?? false)
                                    ? widget.item.visibleIf![i].questionId
                                    : null,
                                items: widget.targetQuestionOptions
                                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                                    .toList(),
                                onChanged: (v) {
                                  final list = List<VisibleCondition>.of(widget.item.visibleIf ?? const <VisibleCondition>[]);
                                  list[i] = VisibleCondition(questionId: v ?? '', op: cond.op, value: cond.value);
                                  widget.onChanged(QuestionItem(
                                    id: widget.item.id,
                                    type: widget.item.type,
                                    label: _labelCtrl.text,
                                    required: widget.item.required,
                                    options: widget.item.options,
                                    allowAttachment: widget.item.allowAttachment,
                                    multiLine: widget.item.multiLine,
                                    visibleIf: list,
                                  ));
                                  setState(() {});
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('ql-cond-${widget.item.id}-$i-val'),
                            initialValue: cond.value,
                            decoration: const InputDecoration(labelText: 'Value', border: OutlineInputBorder()),
                            onChanged: (v) {
                              final list = List<VisibleCondition>.of(widget.item.visibleIf ?? const <VisibleCondition>[]);
                              list[i] = VisibleCondition(questionId: cond.questionId, op: cond.op, value: v);
                              widget.onChanged(QuestionItem(
                                id: widget.item.id,
                                type: widget.item.type,
                                label: _labelCtrl.text,
                                required: widget.item.required,
                                options: widget.item.options,
                                allowAttachment: widget.item.allowAttachment,
                                multiLine: widget.item.multiLine,
                                visibleIf: list,
                              ));
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () {
                            final list = List<VisibleCondition>.of(widget.item.visibleIf ?? const <VisibleCondition>[]);
                            list.removeAt(i);
                            widget.onChanged(QuestionItem(
                              id: widget.item.id,
                              type: widget.item.type,
                              label: _labelCtrl.text,
                              required: widget.item.required,
                              options: widget.item.options,
                              allowAttachment: widget.item.allowAttachment,
                              multiLine: widget.item.multiLine,
                              visibleIf: list,
                            ));
                            setState(() {});
                          },
                          icon: const Icon(Icons.delete_outline),
                        )
                      ],
                    ),
                  );
                }).toList(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      final list = List<VisibleCondition>.of(widget.item.visibleIf ?? const <VisibleCondition>[]);
                      list.add(VisibleCondition(questionId: '', op: 'equals', value: ''));
                      widget.onChanged(QuestionItem(
                        id: widget.item.id,
                        type: widget.item.type,
                        label: _labelCtrl.text,
                        required: widget.item.required,
                        options: widget.item.options,
                        allowAttachment: widget.item.allowAttachment,
                        multiLine: widget.item.multiLine,
                        visibleIf: list,
                      ));
                      setState(() {});
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add condition'),
                  ),
                ),
              ],
            ),
            // Attachments are now represented as dedicated answer types (Media/Sketch/Annotation/Signature)
          ],
        ),
      ),
    );
  }
}
