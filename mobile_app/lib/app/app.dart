import 'package:flutter/material.dart';

import '../features/auth/presentation/login_screen.dart';

/// Root widget of the TANFINET POP PM Monitoring field app.
///
/// Starts on the employee login screen. POP selection, camera/GPS
/// capture, offline sync and dashboards are implemented in later steps,
/// under lib/features/.
class TanfinetPmApp extends StatelessWidget {
  const TanfinetPmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TANFINET POP PM Monitoring',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const LoginScreen(),
    );
  }
}
