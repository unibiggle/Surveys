import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../surveys/survey_runner_page.dart';

class SurveysPage extends ConsumerWidget {
  const SurveysPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(surveyRepositoryProvider);
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Surveys')),
      body: StreamBuilder(
        stream: repo.watchAllSurveys(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final items = snapshot.data!;
          if (items.isEmpty) return const Center(child: Text('No surveys yet'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final s = items[index];
              return FutureBuilder(
                future: (db.select(db.templates)..where((t) => t.id.equals(s.templateId))).getSingle(),
                builder: (context, templateSnap) {
                  final templateName = templateSnap.data?.name ?? 'Template';
                  return ListTile(
                    title: Text('$templateName • ${s.status}'),
                    subtitle: Text('Started: ${s.createdAt.toLocal()}'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SurveyRunnerPage(surveyId: s.id, templateId: s.templateId)),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

