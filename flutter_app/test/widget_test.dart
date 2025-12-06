// Basic Flutter widget test for Sweep Dreams app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sweep_dreams/main.dart';

void main() {
  testWidgets('App renders with header and location button',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SweepDreamsApp());

    // Verify the app title is displayed.
    expect(find.text('SWEEP DREAMS'), findsOneWidget);

    // Verify the subtitle is displayed.
    expect(find.text('Move your car before the next street sweep'),
        findsOneWidget);

    // Verify the location button is present.
    expect(find.text('Use my location'), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });
}
