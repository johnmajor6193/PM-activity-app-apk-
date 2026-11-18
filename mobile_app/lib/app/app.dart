import 'package:flutter/material.dart';

import '../features/auth/presentation/login_screen.dart';

/// Root widget of the TANFINET POP PM Monitoring field app.
///
/// Starts on the employee login screen. POP selection, camera/GPS
/// capture, GPS watermarking, offline storage/sync, Google Drive
/// upload, and PM visit submission are all implemented under
/// lib/features/pm_visit/ and lib/features/location_selection/;
/// dashboards and MIS export are not yet built.
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
