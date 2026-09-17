import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexterm/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
  });
  testWidgets('four agent cards lead dashboard even without skills', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NextermApp());
    await tester.pump();
    final titles = [
      'Codex',
      'Claude Code',
      'Session Codex',
      'Session Claude Code',
    ];
    for (final title in titles) {
      expect(find.text(title), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(title)).dy,
        lessThan(tester.getTopLeft(find.text('Skills')).dy),
      );
    }
    expect(
      tester.getTopLeft(find.text('Codex')).dy,
      lessThan(tester.getTopLeft(find.text('Session Codex')).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
