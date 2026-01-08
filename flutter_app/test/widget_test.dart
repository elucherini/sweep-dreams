// Basic Flutter widget test for Sweep Dreams app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sweep_dreams/main.dart';
import 'package:sweep_dreams/screens/map_home_screen.dart';

void main() {
  testWidgets('App renders map home UI', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SweepDreamsApp());
    await tester.pump();

    // Verify core map-home scaffolding is present.
    expect(find.byType(MapHomeScreen), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
