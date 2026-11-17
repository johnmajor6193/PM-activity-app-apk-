import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/app/app.dart';

void main() {
  testWidgets('App starts on the employee login screen', (tester) async {
    await tester.pumpWidget(const TanfinetPmApp());

    expect(find.text('Employee Login'), findsOneWidget);
    expect(find.text('Employee ID'), findsOneWidget);
    expect(find.text('Mobile Number'), findsOneWidget);
  });

  testWidgets('Shows validation errors for empty fields', (tester) async {
    await tester.pumpWidget(const TanfinetPmApp());

    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pump();

    expect(find.text('Employee ID is required'), findsOneWidget);
    expect(find.text('Mobile number is required'), findsOneWidget);
  });
}
