import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's own Android code (android/app/src/main/kotlin/...):
///
/// * `CallPushReceiver` + `CallEngine` hand each Vobiz push to the app's one
///   Flutter engine, which also runs the SIP connection and the UI, starting
///   it (headless) when the app was closed;
/// * `CallService`, the foreground service (types `phoneCall|microphone`)
///   that keeps the microphone and the process alive during a call.
///
/// Every method is a no-op where that code is missing (tests, iOS).
class CallPlatform {
  CallPlatform() : _channel = const MethodChannel(channelName) {
    if (_supported) _channel.setMethodCallHandler(_onNativeCall);
  }

  /// For tests: talks to nothing.
  @visibleForTesting
  CallPlatform.forTesting() : _channel = const MethodChannel('$channelName/test');

  static const String channelName = 'vobiz.demo/call';

  final MethodChannel _channel;
  final StreamController<Map<String, String>> _pushes = StreamController<Map<String, String>>.broadcast();
  final StreamController<void> _hangUps = StreamController<void>.broadcast();

  static bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Vobiz pushes as Android received them: with the app open, in the
  /// background, or started by the push itself.
  Stream<Map<String, String>> get pushes => _pushes.stream;

  /// "Hang up" on the ongoing-call notification.
  Stream<void> get hangUpRequests => _hangUps.stream;

  /// Tells Android the Dart side listens now. Returns the pushes that arrived
  /// before (typically the push that started the app).
  Future<List<Map<String, String>>> ready() async {
    final raw = await _invoke<List<Object?>>('ready');
    return <Map<String, String>>[
      for (final item in raw ?? const <Object?>[])
        if (item is Map) item.map((k, v) => MapEntry('$k', '$v')),
    ];
  }

  /// This app's package name and version, for the push registration.
  Future<({String packageName, String version})> appInfo() async {
    final raw = await _invoke<Map<Object?, Object?>>('appInfo');
    return (
      packageName: '${raw?['packageName'] ?? ''}',
      version: '${raw?['versionName'] ?? ''}',
    );
  }

  /// Starts the call's foreground service. Call it while the app is visible
  /// or right after the user's tap: Android 14 refuses a microphone service
  /// started from the background.
  Future<void> startCallService({required String caller, required bool outbound}) =>
      _invoke<void>('startCallService', <String, Object>{'caller': caller, 'outbound': outbound});

  /// The call is over.
  Future<void> stopCallService() => _invoke<void>('stopCallService');

  Future<Object?> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'push':
        final args = call.arguments;
        if (args is Map) _pushes.add(args.map((k, v) => MapEntry('$k', '$v')));
      case 'hangUp':
        _hangUps.add(null);
    }
    return null;
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('Call platform: $method failed: ${e.code} ${e.message}');
      return null;
    }
  }
}
