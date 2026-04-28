import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

const _kChannelId = 'vobiz_incoming_calls';
const _kNotificationId = 1001;

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

// ---------------------------------------------------------------------------
// Top-level background message handler — runs in an isolate when app is killed
// or backgrounded. Must be top-level (not a class method).
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final sentTime = message.sentTime;
  if (sentTime != null && DateTime.now().difference(sentTime).inSeconds > 30) return;

  final data = message.data;
  if (data['type'] != 'inbound_call') return;

  final caller = data['caller'] ?? 'Unknown';
  final backendUrl = data['backend_url'] ?? '';

  await _localNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  await _showIncomingCallNotification(caller: caller, backendUrl: backendUrl);
}

// ---------------------------------------------------------------------------
// Top-level notification action handler — called when user taps Decline/Answer
// buttons on the notification (runs in a background isolate on Android 12+).
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
void onNotificationAction(NotificationResponse response) {
  final actionId = response.actionId;
  final payload = response.payload ?? '';

  if (actionId == 'decline') {
    // Fire-and-forget: POST decline to backend so the PSTN leg is hung up.
    if (payload.isNotEmpty) {
      http
          .post(Uri.parse('$payload/decline-inbound'))
          .catchError((_) => http.Response('', 500));
    }
  }
  // 'answer' action has showsUserInterface: true and cancelNotification: true,
  // so the app launches automatically — no extra work needed here.
}

// ---------------------------------------------------------------------------
// Internal helper to show the incoming call notification
// ---------------------------------------------------------------------------

Future<void> _showIncomingCallNotification({
  required String caller,
  required String backendUrl,
}) async {
  const androidDetails = AndroidNotificationDetails(
    _kChannelId,
    'Incoming Calls',
    channelDescription: 'Notifications for incoming VoBiz calls',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.call,
    ongoing: true,
    autoCancel: false,
    actions: [
      AndroidNotificationAction(
        'decline',
        'Decline',
        showsUserInterface: false,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        'answer',
        'Answer',
        showsUserInterface: true,
        cancelNotification: true,
      ),
    ],
  );

  await _localNotifications.show(
    _kNotificationId,
    'Incoming Call',
    caller,
    const NotificationDetails(android: androidDetails),
    payload: backendUrl,
  );
}

// ---------------------------------------------------------------------------
// FcmService — initialise once from main() and call helpers as needed
// ---------------------------------------------------------------------------

class FcmService {
  FcmService._();

  /// Call once from main() after Firebase.initializeApp().
  static Future<void> initialize() async {
    // Create the Android notification channel.
    const channel = AndroidNotificationChannel(
      _kChannelId,
      'Incoming Calls',
      description: 'Notifications for incoming VoBiz calls',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Initialise the plugin with the action callback.
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: onNotificationAction,
      onDidReceiveBackgroundNotificationResponse: onNotificationAction,
    );

    // Request FCM permission (iOS / Android 13+).
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground message listener.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final data = message.data;
      if (data['type'] != 'inbound_call') return;
      final caller = data['caller'] ?? 'Unknown';
      final backendUrl = data['backend_url'] ?? '';
      await _showIncomingCallNotification(
          caller: caller, backendUrl: backendUrl);
    });
  }

  /// Registers the device FCM token with the backend after login.
  static Future<void> registerWithBackend({
    required String backendUrl,
    required String username,
  }) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await http.post(
        Uri.parse('$backendUrl/register-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'token': token,
          'backend_url': backendUrl,
        }),
      );
    } catch (e) {
      // Non-fatal: push notifications simply won't work for this session.
      assert(() {
        // ignore: avoid_print
        print('[FcmService] registerWithBackend error: $e');
        return true;
      }());
    }
  }

  /// Dismisses the incoming call notification (e.g., after user answers in-app).
  static void dismissCallNotification() {
    _localNotifications.cancel(_kNotificationId);
  }

  /// Returns true if the app was launched by tapping the "Answer" action button.
  static Future<bool> wasLaunchedFromAnswerAction() async {
    final details =
        await _localNotifications.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return false;
    return details.notificationResponse?.actionId == 'answer';
  }
}
