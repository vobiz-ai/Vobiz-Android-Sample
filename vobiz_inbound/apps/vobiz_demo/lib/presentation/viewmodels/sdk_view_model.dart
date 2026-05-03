import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vobiz_webrtc/vobiz_webrtc.dart';

import '../../integration/sdk_factory.dart';
import '../../services/fcm_service.dart';

/// View model responsible for SDK authentication and connection state.
class SdkViewModel extends ChangeNotifier {
  SdkViewModel({required SdkFactory factory})
    : _client = factory.createClient() {
    _connectionSub = _client.connectionEvents.listen((ConnectionEvent event) {
      connectionEvent = event;
      isBusy = false;
      notifyListeners();
    });

    _callSub = _client.callEvents.listen((CallEvent event) {
      latestCallEvent = event;
      notifyListeners();
    });

    _errorSub = _client.errorEvents.listen((ErrorEvent event) {
      latestError = event;
      isBusy = false;
      errorMessage = event.message;
      notifyListeners();
    });
  }

  final VobizClient _client;

  ConnectionEvent? connectionEvent;
  CallEvent? latestCallEvent;
  ErrorEvent? latestError;
  bool isBusy = false;
  String? errorMessage;
  String? loggedInUsername;

  StreamSubscription<ConnectionEvent>? _connectionSub;
  StreamSubscription<CallEvent>? _callSub;
  StreamSubscription<ErrorEvent>? _errorSub;

  VobizClient get client => _client;

  bool get isConnected => _client.isConnected;

  /// Performs SDK login with username and password.
  /// Returns true only after SIP registration is confirmed (not just connected).
  Future<bool> login(String username, String password) async {
    errorMessage = null;
    latestError = null;
    isBusy = true;
    notifyListeners();

    try {
      // Opens WebSocket and sends REGISTER — does not wait for 200 OK.
      await _client.connect(
        CredentialConfig(username: username, password: password),
      );

      // Wait for the SIP registration response (up to 10 s).
      final completer = Completer<bool>();
      late StreamSubscription<ConnectionEvent> sub;
      sub = _client.connectionEvents.listen((ConnectionEvent event) {
        if (completer.isCompleted) return;
        if (event.registrationState == RegistrationState.registered) {
          sub.cancel();
          completer.complete(true);
        } else if (event.registrationState == RegistrationState.failed) {
          sub.cancel();
          completer.complete(false);
        }
      });

      final registered = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          sub.cancel();
          return false;
        },
      );

      if (!registered) {
        errorMessage = errorMessage ?? 'SIP registration timed out';
        return false;
      }

      loggedInUsername = username;
      FcmService.registerWithBackend(
        backendUrl: SdkFactory.backendUrl,
        username: username,
      );
      return true;
    } catch (error) {
      errorMessage = error.toString();
      return false;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  void clearError() {
    errorMessage = null;
    latestError = null;
    notifyListeners();
  }

  Future<void> disconnect() async {
    errorMessage = null;
    await _client.disconnect();
    notifyListeners();
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _callSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}
