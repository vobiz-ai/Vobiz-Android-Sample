import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart' as ck;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart' as ck;

/// The system incoming-call screen (flutter_callkit_incoming): full screen on
/// a locked phone, a heads-up notification with Accept and Decline otherwise.
///
/// Every method swallows platform errors, so the app still works where the
/// plugin is missing (widget tests) or a permission was refused.
class CallScreen {
  const CallScreen();

  /// How long the screen rings before it gives up.
  static const Duration ringFor = Duration(seconds: 45);

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Accept, Decline, timeout and hang-up taps, while the app is running.
  Stream<ck.CallEvent?> get events async* {
    if (!supported) return;
    try {
      await ck.FlutterCallkitIncoming.activeCalls();
    } on MissingPluginException {
      return;
    } on PlatformException {
      // The plugin is there; the call list just could not be read.
    }
    yield* ck.FlutterCallkitIncoming.onEvent;
  }

  /// Rings [id]. [extra] comes back with Accept and Decline, even after the
  /// app was closed.
  Future<void> showIncoming({
    required String id,
    required String caller,
    String subtitle = 'Vobiz call',
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) async {
    if (!supported) return;
    await _guard(() => ck.FlutterCallkitIncoming.showCallkitIncoming(ck.CallKitParams(
          id: id,
          nameCaller: caller.isEmpty ? 'Unknown caller' : caller,
          appName: 'Vobiz Demo',
          handle: subtitle,
          type: 0,
          duration: ringFor.inMilliseconds,
          extra: extra,
          missedCallNotification: const ck.NotificationParams(
            showNotification: false,
            isShowCallback: false,
          ),
          callingNotification: const ck.NotificationParams(
            showNotification: true,
            isShowCallback: true,
            subtitle: 'On a call',
            callbackText: 'Hang up',
          ),
          android: const ck.AndroidParams(
            isCustomNotification: true,
            isShowLogo: false,
            isShowCallID: false,
            isShowFullLockedScreen: true,
            ringtonePath: 'system_ringtone_default',
            backgroundColor: '#0A0C10',
            actionColor: '#16A34A',
            textColor: '#FFFFFF',
            incomingCallNotificationChannelName: 'Incoming calls',
            missedCallNotificationChannelName: 'Missed calls',
            textAccept: 'Accept',
            textDecline: 'Decline',
          ),
          ios: const ck.IOSParams(handleType: 'generic', supportsVideo: false),
        )));
  }

  /// Stops ringing (or ends the ongoing-call notification) for [id].
  Future<void> end(String id) async {
    if (!supported) return;
    await _guard(() => ck.FlutterCallkitIncoming.endCall(id));
  }

  /// Android 13+: the notification permission, without which nothing rings.
  Future<void> requestNotifications() async {
    if (!supported) return;
    await _guard(() => ck.FlutterCallkitIncoming.requestNotificationPermission(<String, String>{
          'title': 'Allow notifications',
          'rationaleMessagePermission': 'Incoming calls ring as a notification. Allow notifications to receive calls.',
          'postNotificationMessageRequired': 'Incoming calls need notifications. Allow them in Settings → Notifications.',
        }));
  }

  /// Android 14+: whether a call may take over a locked screen.
  Future<bool?> canUseFullScreen() async {
    if (!supported) return null;
    return _guard(ck.FlutterCallkitIncoming.canUseFullScreenIntent);
  }

  /// Opens the system setting for full-screen notifications.
  Future<void> requestFullScreen() async {
    if (!supported) return;
    await _guard(ck.FlutterCallkitIncoming.requestFullIntentPermission);
  }

  static Future<T?> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('Call screen: ${e.code} ${e.message}');
      return null;
    }
  }
}
