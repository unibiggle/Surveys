import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories.dart';
import '../../models/template_schema.dart';

class TemplateBuilderPage extends ConsumerStatefulWidget {
  const TemplateBuilderPage({super.key, required this.initialSchema});
  final TemplateSchema initialSchema;

  @override
  ConsumerState<TemplateBuilderPage> createState() => _TemplateBuilderPageState();
}

class _TemplateBuilderPageState extends ConsumerState<TemplateBuilderPage> {
  late TextEditingController _nameCtrl;
  late TemplateSchema _schema;
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _schema = widget.initialSchema;
    _nameCtrl = TextEditingController(text: _schema.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _addQuestion() {
    final section = _schema.sections.first;
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
    final updated = TemplateSchema(
      id: _schema.id.isEmpty ? _uuid.v4() : _schema.id,
      name: _nameCtrl.text.trim().isEmpty ? 'Untitled Template' : _nameCtrl.text.trim(),
      version: _schema.version,
      sections: _schema.sections,
    );
    await repo.createOrUpdateTemplate(updated);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final section = _schema.sections.first;
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
          const SizedBox(height: 16),
          Text(section.title, style: Theme.of(context).textTheme.titleLarge),
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
