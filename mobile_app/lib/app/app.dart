import 'package:flutter/material.dart';

/// Root widget of the TANFINET POP PM Monitoring field app.
///
/// This is scaffold only: it shows a placeholder home screen so the project
/// can be built and run. Login, location selection, camera capture, GPS,
/// geofencing, offline sync and dashboards are implemented in later steps,
/// under lib/features/.
class TanfinetPmApp extends StatelessWidget {
  const TanfinetPmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TANFINET POP PM Monitoring',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const _ScaffoldPlaceholderScreen(),
    );
  }
}

class _ScaffoldPlaceholderScreen extends StatelessWidget {
  const _ScaffoldPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TANFINET POP PM Monitoring')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Project scaffold.\n'
            'Login, POP selection, camera/GPS capture, offline sync and '
            'dashboards will be added in later development steps.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
