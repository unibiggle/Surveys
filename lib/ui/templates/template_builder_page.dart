import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories.dart';
import '../../data/session_providers.dart';
import '../../services/sync_service.dart';
import '../../services/attachments_service.dart';
import '../../data/providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/template_schema.dart';

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

  @override
  void initState() {
    super.initState();
    _schema = widget.initialSchema;
    _nameCtrl = TextEditingController(text: _schema.name);
    _brandCtrl = TextEditingController(text: _schema.brandName ?? '');
    _logoCtrl = TextEditingController(text: _schema.brandLogoUrl ?? '');
    _logoStorageCtrl = TextEditingController(text: _schema.brandLogoStoragePath ?? '');
    _initPublished();
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
      _schema.sections.add(TemplateSection(id: _uuid.v4(), title: 'New Section', items: []));
      _currentSectionIndex = _schema.sections.length - 1;
    });
  }

  void _deleteCurrentSection() {
    if (_schema.sections.length <= 1) return;
    setState(() {
      _schema.sections.removeAt(_currentSectionIndex);
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
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _brandCtrl,
                decoration: const InputDecoration(labelText: 'Brand name (optional)', border: OutlineInputBorder()),
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
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(labelText: 'Section title', border: OutlineInputBorder()),
            controller: TextEditingController(text: section.title),
            onChanged: (v) => setState(() => _schema.sections[_currentSectionIndex] = TemplateSection(id: section.id, title: v, description: section.description, items: section.items)),
          ),
          const SizedBox(height: 8),
          if (section.description != null)
            Text(section.description!),
          const SizedBox(height: 8),
          ...section.items.map((q) => _QuestionEditor(
                key: ValueKey(q.id),
                item: q,
                onChanged: (updated) {
                  final idx = section.items.indexWhere((e) => e.id == updated.id);
                  setState(() {
                    section.items[idx] = updated;
                  });
                },
                onDelete: () {
                  setState(() {
                    section.items.removeWhere((e) => e.id == q.id);
                  });
                },
              )),
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
  const _QuestionEditor({super.key, required this.item, required this.onChanged, required this.onDelete});
  final QuestionItem item;
  final ValueChanged<QuestionItem> onChanged;
  final VoidCallback onDelete;

  @override
  State<_QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<_QuestionEditor> {
  late TextEditingController _labelCtrl;
  late TextEditingController _optionsCtrl; // comma-separated for singleChoice

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.item.label);
    _optionsCtrl = TextEditingController(text: (widget.item.options ?? []).join(','));
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _optionsCtrl.dispose();
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
              decoration: const InputDecoration(
                labelText: 'Question label',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _emitChanged(label: v),
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
            Row(
              children: [
                const Text('Allow attachments'),
                const SizedBox(width: 8),
                Switch(
                  value: widget.item.allowAttachment,
                  onChanged: (v) {
                    widget.onChanged(QuestionItem(
                      id: widget.item.id,
                      type: widget.item.type,
                      label: _labelCtrl.text,
                      required: widget.item.required,
                      options: widget.item.options,
                      allowAttachment: v,
                    ));
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
