import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Firebase Cloud Messaging: this phone's push token, and pushes that arrive
/// while the app is open.
///
/// Push is optional. Without `android/app/google-services.json` the app still
/// rings for calls while it is open; [available] is false and [problem] says
/// why.
class PushService {
  PushService._({required this.available, this.problem});

  /// For tests and builds without push.
  PushService.unavailable(String this.problem) : available = false;

  final bool available;
  final String? problem;

  /// Starts Firebase, before `runApp`. Never throws.
  static Future<PushService> start() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return PushService._(available: false, problem: 'Closed-app calls are Android-only for now.');
    }
    try {
      await Firebase.initializeApp();
    } catch (_) {
      return PushService._(
        available: false,
        problem: 'Firebase is not set up in this build: add android/app/google-services.json '
            'and rebuild to ring this phone when the app is closed.',
      );
    }
    // No Dart background handler on purpose: it would start a second Flutter
    // engine for every push. CallPushReceiver.kt hands each Vobiz push to the
    // app's one engine (CallEngine.kt), which also runs the SIP connection.
    return PushService._(available: true);
  }

  /// This phone's Firebase token, or null without Firebase or a network.
  Future<String?> token() async {
    if (!available) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  /// Firebase replaces tokens now and then; Vobiz must get the new one.
  Stream<String> get tokenRefresh =>
      available ? FirebaseMessaging.instance.onTokenRefresh : const Stream<String>.empty();

  /// Push data that arrives while the app is in the foreground. The same push
  /// also comes through CallPlatform.pushes; the controller handles each once.
  Stream<Map<String, String>> get foregroundData => available
      ? FirebaseMessaging.onMessage.map((m) => m.data.map((k, v) => MapEntry(k, '$v')))
      : const Stream<Map<String, String>>.empty();

  /// Android 13+: asks for the notification permission, without which a
  /// closed app cannot ring.
  Future<void> requestNotificationPermission() async {
    if (!available) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}
  }
}
