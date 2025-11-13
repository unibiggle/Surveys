import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/session_providers.dart';
import 'auth/sign_in_page.dart';
import 'home_page.dart';
import 'teams/teams_page.dart';

class SessionGate extends ConsumerStatefulWidget {
  const SessionGate({super.key});

  @override
  ConsumerState<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends ConsumerState<SessionGate> {
  late final Stream<AuthState> _authStream;

  @override
  void initState() {
    super.initState();
    _authStream = Supabase.instance.client.auth.onAuthStateChange;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authStream,
      initialData: AuthState(AuthChangeEvent.initialSession, Supabase.instance.client.auth.currentSession),
      builder: (context, snap) {
        final session = snap.data?.session;
        if (session == null) {
          return const SignInPage();
        }
        final selected = ref.watch(selectedTeamProvider);
        if (selected == null) {
          return const TeamsPage();
        }
        return const HomePage();
      },
    );
  }
}
