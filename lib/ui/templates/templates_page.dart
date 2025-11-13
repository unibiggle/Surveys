import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';

import '../../data/repositories.dart';
import '../../models/template_schema.dart';
import '../../data/session_providers.dart';
import '../../utils/template_importer.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../surveys/survey_runner_page.dart';
import 'template_builder_page.dart';

class TemplatesPage extends ConsumerWidget {
  const TemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(templateRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'seed') {
                await _seedSampleTemplates(context, ref);
              } else if (v == 'import_basic') {
                await _importBasicFromAsset(context, ref);
              } else if (v == 'import_from_file') {
                await _importFromFile(context, ref);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'seed', child: Text('Seed sample templates')),
              PopupMenuItem(value: 'import_basic', child: Text('Import Lift BASIC from asset')), 
              PopupMenuItem(value: 'import_from_file', child: Text('Import from .txt file')), 
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // Create a new empty schema and open builder
          final schema = TemplateSchema(
            id: '',
            name: 'Untitled Template',
            version: 1,
            sections: [
              TemplateSection(id: UniqueKey().toString(), title: 'Section 1', items: []),
            ],
          );
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TemplateBuilderPage(initialSchema: schema)),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('New Template'),
      ),
      body: StreamBuilder(
        stream: repo.watchAllTemplates(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(child: Text('No templates yet'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final t = items[index];
              return ListTile(
                title: Text(t.name),
                subtitle: Text('v${t.version} • ${t.published ? 'Published' : 'Draft'}'),
                onTap: () async {
                  final schema = TemplateSchema.decode(t.schemaJson);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TemplateBuilderPage(initialSchema: schema)),
                  );
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_arrow),
                      tooltip: 'Start Survey',
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => SurveyRunnerLauncher(template: t)),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete Template',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete template?'),
                            content: Text('Delete ${t.name}? This cannot be undone.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref.read(templateRepositoryProvider).deleteTemplate(t.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template deleted')));
                          }
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> _seedSampleTemplates(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(templateRepositoryProvider);
  final team = ref.read(selectedTeamProvider);
  final uuid = const Uuid();

  TemplateSchema liftBasic() {
    final sectionId = uuid.v4();
    return TemplateSchema(
      id: '',
      name: 'Lift Survey (BASIC)',
      version: 1,
      sections: [
        TemplateSection(
          id: sectionId,
          title: 'General',
          items: [
            QuestionItem(id: uuid.v4(), type: QuestionType.text, label: 'Location / Project'),
            QuestionItem(id: uuid.v4(), type: QuestionType.yesNoNa, label: 'Lift accessible'),
            QuestionItem(id: uuid.v4(), type: QuestionType.yesNoNa, label: 'Lift functional'),
            QuestionItem(
              id: uuid.v4(),
              type: QuestionType.singleChoice,
              label: 'Power phase',
              options: const ['Single-phase', 'Three-phase', 'Unknown'],
            ),
            QuestionItem(
              id: uuid.v4(),
              type: QuestionType.multiChoice,
              label: 'Observed issues',
              options: const [
                'Hydraulic leak',
                'Oil contamination',
                'Chain wear',
                'Safety lock fault',
                'Electrical fault',
                'Corrosion',
              ],
              allowAttachment: true,
            ),
            QuestionItem(
              id: uuid.v4(),
              type: QuestionType.dropdown,
              label: 'Priority',
              options: const ['Low', 'Medium', 'High', 'Critical'],
            ),
            QuestionItem(id: uuid.v4(), type: QuestionType.likert5, label: 'Overall condition'),
            QuestionItem(id: uuid.v4(), type: QuestionType.text, label: 'Notes', allowAttachment: true),
          ],
        ),
      ],
    );
  }

  TemplateSchema preTestChecklist() {
    final sectionId = uuid.v4();
    return TemplateSchema(
      id: '',
      name: 'Pre Test Item Checklist',
      version: 1,
      sections: [
        TemplateSection(
          id: sectionId,
          title: 'Checklist',
          items: [
            QuestionItem(id: uuid.v4(), type: QuestionType.yesNoNa, label: 'Work area clear'),
            QuestionItem(id: uuid.v4(), type: QuestionType.yesNoNa, label: 'PPE worn'),
            QuestionItem(id: uuid.v4(), type: QuestionType.yesNoNa, label: 'Capacity plate visible'),
            QuestionItem(id: uuid.v4(), type: QuestionType.yesNoNa, label: 'Safety lock operable'),
            QuestionItem(id: uuid.v4(), type: QuestionType.yesNoNa, label: 'Emergency stop functioning'),
            QuestionItem(id: uuid.v4(), type: QuestionType.yesNoNa, label: 'Cables/Chains inspected'),
            QuestionItem(id: uuid.v4(), type: QuestionType.yesNoNa, label: 'Hydraulic system inspected'),
            QuestionItem(id: uuid.v4(), type: QuestionType.yesNoNa, label: 'Electrical system inspected'),
            QuestionItem(id: uuid.v4(), type: QuestionType.yesNoNa, label: 'Anchorage secure'),
            QuestionItem(id: uuid.v4(), type: QuestionType.text, label: 'Additional comments', allowAttachment: true),
          ],
        ),
      ],
    );
  }

  await repo.createOrUpdateTemplate(liftBasic(), teamId: team?.id);
  await repo.createOrUpdateTemplate(preTestChecklist(), teamId: team?.id);

  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seeded sample templates')));
}

Future<void> _importBasicFromAsset(BuildContext context, WidgetRef ref) async {
  try {
    final txt = await rootBundle.loadString('Templates/lift_basic.txt');
    final schema = TemplateImporter.parseLiftBasicTxt(txt);
    final repo = ref.read(templateRepositoryProvider);
    final team = ref.read(selectedTeamProvider);
    await repo.createOrUpdateTemplate(schema, teamId: team?.id);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Imported Lift BASIC template')));
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
  }
}

Future<void> _importFromFile(BuildContext context, WidgetRef ref) async {
  try {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt'], withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final content = String.fromCharCodes(file.bytes!);
    final schema = TemplateImporter.parseLiftBasicTxt(content);
    final repo = ref.read(templateRepositoryProvider);
    final team = ref.read(selectedTeamProvider);
    await repo.createOrUpdateTemplate(schema, teamId: team?.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Imported template from file')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }
}
