import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'services/fcm_service.dart';

// Top-level background handler wrapper (must be top-level, not a class method).
@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage msg) =>
    firebaseMessagingBackgroundHandler(msg);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_bgHandler);
  await FcmService.initialize();
  runApp(const VobizDemoApp());
}
