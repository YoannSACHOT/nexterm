import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nexterm/main.dart';

void main() {
  testWidgets('App boots without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const NextermApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
