import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/app/app.dart';

void main() {
  testWidgets('App renders the placeholder home screen', (tester) async {
    await tester.pumpWidget(const TanfinetPmApp());

    expect(find.text('TANFINET POP PM Monitoring'), findsOneWidget);
  });
}
