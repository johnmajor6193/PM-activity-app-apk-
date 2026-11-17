import 'package:flutter/material.dart';

import '../domain/entities/employee_profile.dart';
import 'login_screen.dart';

/// Shows the logged-in employee's basic profile: Employee ID, name, and
/// assigned district.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.profile});

  final EmployeeProfile profile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileRow(label: 'Employee ID', value: profile.employeeId),
            const SizedBox(height: 16),
            _ProfileRow(label: 'Name', value: profile.name),
            const SizedBox(height: 16),
            _ProfileRow(
              label: 'Assigned District',
              value: profile.assignedDistrict ?? 'Not assigned',
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              child: const Text('Log out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
