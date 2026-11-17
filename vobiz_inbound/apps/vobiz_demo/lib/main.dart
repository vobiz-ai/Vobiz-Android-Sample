import 'package:flutter/material.dart';

import 'app.dart';
import 'services/push/push_service.dart';

/// The Vobiz Flutter sample: a softphone that calls phones, is called on your
/// Vobiz number, and rings while closed through Vobiz push.
///
/// Also started headless by a push when the app is closed (CallEngine.kt):
/// the PhoneController then shows the call screen and signs in, before any
/// screen is visible.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final push = await PushService.start();
  runApp(VobizDemoApp(push: push));
}
