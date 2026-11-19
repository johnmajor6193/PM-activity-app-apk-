import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/auth/domain/entities/employee_profile.dart';
import 'package:mobile_app/features/auth/presentation/profile_screen.dart';
import 'package:mobile_app/features/dashboard/presentation/dashboard_screen.dart';

/// Verifies the one navigation hop this Dashboard module actually
/// added: ProfileScreen's "View Dashboard" button. Login -> Profile
/// itself is pre-existing/unchanged and already covered by
/// test/app_test.dart and auth_controller_test.dart; chaining through
/// a real login here would only re-test that, not this module.
void main() {
  testWidgets('tapping "View Dashboard" on the profile screen opens DashboardScreen', (
    tester,
  ) async {
    const profile = EmployeeProfile(employeeId: 'ENG001', name: 'Dev Test Engineer', assignedDistrict: 'Chennai');

    await tester.pumpWidget(const MaterialApp(home: ProfileScreen(profile: profile)));

    expect(find.text('View Dashboard'), findsOneWidget);

    await tester.tap(find.text('View Dashboard'));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsOneWidget);
  });
}
