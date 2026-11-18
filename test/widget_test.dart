import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mysecureapp/main.dart';

void main() {
  const channel = MethodChannel('com.example.mysecureapp/app_locker');
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows setup steps and installed apps', (
    WidgetTester tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'getApps':
          return [
            {'packageName': 'com.example.mail', 'name': 'Mail'},
          ];
        case 'getLockedPackages':
          return <String>[];
        case 'hasPin':
        case 'hasAccessibilityPermission':
          return false;
        default:
          return null;
      }
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(const AppLockerApp());
    await tester.pumpAndSettle();

    expect(find.text('App Locker'), findsOneWidget);
    expect(find.text('Create a PIN'), findsOneWidget);
    expect(find.text('Enable app monitoring'), findsOneWidget);
    expect(find.text('Mail'), findsOneWidget);
    expect(find.text('Protection is on'), findsNothing);
  });

  testWidgets('prompts to create a PIN before locking an app', (
    WidgetTester tester,
  ) async {
    var pinConfigured = false;
    var lockedPackages = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'getApps':
          return [
            {'packageName': 'com.example.mail', 'name': 'Mail'},
          ];
        case 'getLockedPackages':
          return lockedPackages;
        case 'hasPin':
          return pinConfigured;
        case 'hasAccessibilityPermission':
          return false;
        case 'setPin':
          pinConfigured = true;
          return null;
        case 'setLockedPackages':
          lockedPackages = List<String>.from(
            (call.arguments as Map<Object?, Object?>)['packages'] as List,
          );
          return null;
        default:
          return null;
      }
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(const AppLockerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(find.text('Set a PIN first'), findsOneWidget);
    await tester.tap(find.text('Set PIN'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '1234');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Save PIN'));
    await tester.pumpAndSettle();

    expect(find.text('PIN is set'), findsOneWidget);
    expect(find.text('1 locked'), findsOneWidget);
    expect(lockedPackages, ['com.example.mail']);
  });
}
