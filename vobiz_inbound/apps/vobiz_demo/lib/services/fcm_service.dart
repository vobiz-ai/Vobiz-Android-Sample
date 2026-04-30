import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
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

// Top-level background handler wrapper (must be top-level, not a class method).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final sentTime = message.sentTime;
  if (sentTime != null && DateTime.now().difference(sentTime).inSeconds > 30) return;

  final data = message.data;
  if (data['type'] != 'inbound_call') return;

  final caller = data['caller'] ?? 'Unknown';
  final backendUrl = data['backend_url'] ?? '';
  final roomId = data['room_id'] ?? '';

  // Store notification data for killed-app recovery
  _lastNotificationPayload = backendUrl;
  _lastInboundCallData = {
    'caller': caller,
    'backend_url': backendUrl,
    if (roomId.isNotEmpty) 'room_id': roomId,
  };

  await _localNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  await _showIncomingCallNotification(caller: caller, backendUrl: backendUrl);
}

// ---------------------------------------------------------------------------
// Top-level notification action handler — called when user taps Decline/Answer
// buttons on the notification (runs in the main isolate when app is alive,
// otherwise in a background isolate on Android 12+).
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
void onNotificationAction(NotificationResponse response) {
  final actionId = response.actionId;
  final payload = response.payload ?? '';

  if (actionId == 'decline') {
    if (payload.isNotEmpty) {
      http
          .post(Uri.parse('$payload/decline-inbound'))
          .catchError((_) => http.Response('', 500));
    }
  } else if (actionId == 'answer') {
    // When the app is already running (background), emit on the stream so
    // DialerScreen can immediately join the call without re-login.
    FcmService.notifyAnswerTapped();
  }
}

// Store the last inbound call data from push notification for killed-app recovery
String? _lastNotificationPayload;
Map<String, String>? _lastInboundCallData;

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

  // Emitted when the user taps the Answer action on an in-app notification
  // (foreground/background case). Killed-app case is handled separately via
  // wasLaunchedFromAnswerAction().
  static final StreamController<void> _answerTappedController =
      StreamController<void>.broadcast();

  static Stream<void> get answerTapped => _answerTappedController.stream;

  // Stream that emits foreground inbound call data so the UI can show
  // an in-app dialog instead of a system notification.
  static final StreamController<Map<String, String>> _foregroundCallController =
      StreamController<Map<String, String>>.broadcast();

  static Stream<Map<String, String>> get foregroundInboundCalls =>
      _foregroundCallController.stream;

  // Held so Dart's GC never cancels the subscription.
  static StreamSubscription<RemoteMessage>? _onMessageSub;

  /// Called from onNotificationAction when the Answer button is tapped.
  static void notifyAnswerTapped() {
    _answerTappedController.add(null);
  }

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

    // Foreground: emit on stream so the UI shows an in-app dialog,
    // not a system notification (the app is already open).
    // Stored in _onMessageSub so the GC never cancels this subscription.
    _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final data = message.data;
      if (data['type'] != 'inbound_call') return;
      _foregroundCallController.add(<String, String>{
        'caller': data['caller'] ?? 'Unknown',
        'backend_url': data['backend_url'] ?? '',
      });
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
    try {
      final details = await _localNotifications.getNotificationAppLaunchDetails();
      if (details != null &&
          details.didNotificationLaunchApp &&
          details.notificationResponse?.actionId == 'answer') {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Retrieves the cached inbound call data from the last push notification.
  /// Used when app is killed and launched from the Answer action.
  static Map<String, String>? getLastInboundCallData() {
    return _lastInboundCallData;
  }

  /// No-op — reserved for future use if a persistent flag is added.
  static Future<void> clearPendingAnswer() async {
    _lastInboundCallData = null;
  }
}
