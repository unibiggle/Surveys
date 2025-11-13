import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final url = dotenv.env['SUPABASE_URL'];
    final key = dotenv.env['SUPABASE_ANON_KEY'];
    if (url == null || url.isEmpty || key == null || key.isEmpty) {
      debugPrint('Supabase env not configured. Skipping init.');
      return;
    }
    await Supabase.initialize(url: url, anonKey: key);
    _initialized = true;
  }

  SupabaseClient get client => Supabase.instance.client;
}

