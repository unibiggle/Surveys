import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/supabase_service.dart';
import 'ui/session_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load env for Supabase (optional in local dev)
  await dotenv.load(fileName: '.env', isOptional: true);
  await SupabaseService.instance.init();
  runApp(const ProviderScope(child: SurveysApp()));
}

class SurveysApp extends StatelessWidget {
  const SurveysApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Surveys',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const SessionGate(),
    );
  }
}
