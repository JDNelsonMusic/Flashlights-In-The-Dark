// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flashlights_client/main.dart';

void main() {
  testWidgets('Bootstrap screen shows header and refresh button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FlashlightsApp());
    await tester.pump();

    expect(find.text('Flashlights In The Dark'), findsOneWidget);
    expect(find.byKey(const Key('refreshConnectionButton')), findsOneWidget);
  });
}
