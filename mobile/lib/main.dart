import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'services/auth_state.dart';
import 'utils/format.dart';

void main() {
  runApp(ChangeNotifierProvider(create: (_) => AuthState(), child: const GanacsiApp()));
}

class GanacsiApp extends StatelessWidget {
  const GanacsiApp({super.key});

  ThemeData _theme(Brightness b) {
    final cs = ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E), brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      cardTheme: CardThemeData(
        elevation: 0,
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: cs.surfaceContainerLowest,
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ganacsi AI',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: Consumer<AuthState>(
        builder: (context, auth, _) {
          switch (auth.status) {
            case AuthStatus.loading:
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            case AuthStatus.signedOut:
              return const AuthScreen();
            case AuthStatus.signedIn:
              setCurrency(auth.user!.currency);
              return const HomeShell();
          }
        },
      ),
    );
  }
}
