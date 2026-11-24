import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vobiz_demo/app.dart';
import 'package:vobiz_demo/phone/phone_controller.dart';
import 'package:vobiz_demo/services/backend_api.dart';
import 'package:vobiz_demo/services/push/call_platform.dart';
import 'package:vobiz_demo/services/push/push_service.dart';
import 'package:vobiz_webrtc/vobiz_webrtc.dart';

void main() {
  late PhoneController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    controller = PhoneController(
      client: VobizClient(),
      backend: BackendApi(baseUrl: 'http://localhost:3000', appKey: ''),
      push: PushService.unavailable('No Firebase in tests'),
      platform: CallPlatform.forTesting(),
    );
  });

  Future<void> openApp(WidgetTester tester) async {
    await tester.pumpWidget(VobizDemoApp(push: PushService.unavailable('test'), controller: controller));
    await tester.runAsync(controller.init);
    await tester.pumpAndSettle();
  }

  testWidgets('without a saved sign-in the login screen opens on SIP endpoint', (WidgetTester tester) async {
    await openApp(tester);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Endpoint username'), findsOneWidget);
    expect(find.text('Endpoint password'), findsOneWidget);
    expect(find.text('Remember me'), findsOneWidget);
  });

  testWidgets('the access-token tab asks for an identity only', (WidgetTester tester) async {
    await openApp(tester);
    await tester.tap(find.text('Access token'));
    await tester.pumpAndSettle();
    expect(find.text('Identity'), findsOneWidget);
    expect(find.text('Endpoint password'), findsNothing);
  });

  testWidgets('an empty form is not sent', (WidgetTester tester) async {
    await openApp(tester);
    final button = find.widgetWithText(FilledButton, 'Sign in');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Enter the endpoint username'), findsOneWidget);
    expect(controller.signingIn, isFalse);
  });

  testWidgets('access tokens need the app key in the build', (WidgetTester tester) async {
    await openApp(tester);
    await tester.tap(find.text('Access token'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Identity'), 'alice');
    await tester.runAsync(() => controller.signInWithAccessToken(identity: 'alice'));
    await tester.pumpAndSettle();
    expect(find.textContaining('VOBIZ_APP_KEY'), findsOneWidget);
  });
}
