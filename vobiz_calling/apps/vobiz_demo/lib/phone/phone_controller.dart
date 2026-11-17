import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart' as ck;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vobiz_webrtc/vobiz_webrtc.dart';

import '../integration/app_config.dart';
import '../services/backend_api.dart';
import '../services/push/call_platform.dart';
import '../services/push/call_screen.dart';
import '../services/push/push_service.dart';
import 'numbers.dart';

/// How the app signs in to Vobiz.
enum SignInMode {
  /// A SIP endpoint's username and password (Console → Voice → Endpoints).
  endpoint,

  /// An access token (JWT) that the sample server mints for an identity.
  accessToken,
}

/// A sign-in kept on the phone ("Remember me"), in encrypted storage.
@immutable
class SavedSignIn {
  const SavedSignIn.endpoint({required String this.username, required String this.password})
      : mode = SignInMode.endpoint,
        identity = null;

  const SavedSignIn.accessToken({required String this.identity})
      : mode = SignInMode.accessToken,
        username = null,
        password = null;

  final SignInMode mode;
  final String? username;
  final String? password;
  final String? identity;

  String get label => mode == SignInMode.endpoint ? username! : identity!;
}

/// Whether a call can ring this phone while the app is closed.
enum PushReadiness { off, registering, ready, failed }

/// The phone: sign-in, the one call the SDK runs at a time, and the Vobiz
/// push that wakes the app for a call when it is closed.
///
/// Created once, before any screen (the root widget's state), so it also runs
/// when a push starts the app headless: it shows the system call screen,
/// signs in with the saved sign-in and claims the call Vobiz is holding.
class PhoneController extends ChangeNotifier {
  PhoneController({
    required this.client,
    required this.backend,
    required this.push,
    CallPlatform? platform,
    this.callScreen = const CallScreen(),
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  })  : platform = platform ?? CallPlatform(),
        _storage = storage;

  final VobizClient client;
  final BackendApi backend;
  final PushService push;
  final CallPlatform platform;
  final CallScreen callScreen;
  final FlutterSecureStorage _storage;

  // ── Sign-in ───────────────────────────────────────────────────────────────
  bool initialized = false;
  bool signingIn = false;
  String? signInError;
  SavedSignIn? _saved;
  VobizAccessTokenSession? _tokenSession;
  ConnectionEvent? connection;

  // ── Closed-app calls (Vobiz push) ─────────────────────────────────────────
  PushReadiness pushReadiness = PushReadiness.off;
  String pushDetail = '';

  // ── The call ──────────────────────────────────────────────────────────────
  CallStateStatus callState = CallStateStatus.idle;
  CallDirection? callDirection;
  String remoteParty = '';
  DateTime? connectedAt;
  bool muted = false;
  bool speakerOn = false;

  /// The last thing worth telling the user (a failed call, a transfer).
  String? notice;

  String? _ringingScreenId;
  bool _callServiceRunning = false;
  final Set<String> _closingScreens = <String>{};
  final Set<String> _seenPushes = <String>{};
  final List<StreamSubscription<Object?>> _subs = <StreamSubscription<Object?>>[];

  static const String _kMode = 'vobiz_signin_mode';
  static const String _kUsername = 'vobiz_username';
  static const String _kPassword = 'vobiz_password';
  static const String _kIdentity = 'vobiz_identity';
  static const String _kInstallId = 'vobiz_install_id';

  bool get isRegistered => client.registrationState == RegistrationState.registered;
  bool get hasSavedSignIn => _saved != null;
  SavedSignIn? get savedSignIn => _saved;

  /// The SIP user this phone is signed in as: the endpoint's username, or
  /// `<identity>_<auth id>` with an access token.
  String? get sipUsername => client.sipUsername;

  bool get hasCall =>
      callState != CallStateStatus.idle && callState != CallStateStatus.ended && callState != CallStateStatus.failed;
  bool get isRingingIn => callState == CallStateStatus.incoming;
  bool get isHeld => callState == CallStateStatus.held;
  bool get isConnected => callState == CallStateStatus.active || callState == CallStateStatus.held;

  /// Starts listening, handles a push that started the app, and signs in with
  /// the saved sign-in. Call once.
  Future<void> init() async {
    _subs
      ..add(client.connectionEvents.listen(_onConnection))
      ..add(client.callEvents.listen(_onCall))
      ..add(client.errorEvents.listen(_onError))
      ..add(client.pushCallUpdates.listen(_onPushCallUpdate))
      ..add(callScreen.events.listen(_onCallScreenEvent, onError: (Object _) {}))
      ..add(platform.pushes.listen(_onPushData))
      ..add(push.foregroundData.listen(_onPushData))
      ..add(platform.hangUpRequests.listen((_) => hangup()))
      ..add(push.tokenRefresh.listen((_) => _registerForPush()));
    _saved = await _readSaved();
    // The push that started the app, if it was closed: handled first, so the
    // call screen rings and the sign-in starts at once.
    for (final data in await platform.ready()) {
      _onPushData(data);
    }
    initialized = true;
    notifyListeners();
    final saved = _saved;
    if (saved != null && !signingIn && !client.isConnected) {
      unawaited(_signIn(saved, remember: true));
    }
  }

  // ---------------------------------------------------------------------------
  // Sign-in
  // ---------------------------------------------------------------------------

  Future<bool> signInWithEndpoint({required String username, required String password, bool remember = false}) =>
      _signIn(SavedSignIn.endpoint(username: username.trim(), password: password), remember: remember);

  Future<bool> signInWithAccessToken({required String identity, bool remember = false}) =>
      _signIn(SavedSignIn.accessToken(identity: identity.trim()), remember: remember);

  Future<bool> _signIn(SavedSignIn signIn, {required bool remember}) async {
    if (signingIn) return false;
    signingIn = true;
    signInError = null;
    notifyListeners();
    try {
      await _tokenSession?.dispose();
      _tokenSession = null;
      if (client.connectionState != ConnectionStateStatus.disconnected) await client.disconnect();
      final registered = _waitForRegistration();
      if (signIn.mode == SignInMode.endpoint) {
        await client.connectWithCredentials(
          CredentialConfig(username: signIn.username!, password: signIn.password!),
        );
      } else {
        if (!backend.hasAppKey) {
          throw const BackendException('This build has no VOBIZ_APP_KEY, which the server needs for tokens.');
        }
        _tokenSession = await client.connectWithAccessTokenProvider(backend.tokenProvider(signIn.identity!));
      }
      if (!await registered) {
        signInError ??= 'Vobiz did not accept the sign-in.';
        if (client.registrationState == RegistrationState.failed) await _stopSignIn();
        return false;
      }
      if (remember) {
        await _save(signIn);
      } else {
        await _clearSaved();
      }
      unawaited(_registerForPush());
      return true;
    } catch (e) {
      signInError = _friendly(e);
      await _stopSignIn();
      return false;
    } finally {
      signingIn = false;
      notifyListeners();
    }
  }

  /// Gives up a sign-in Vobiz refused, so the SDK stops retrying it.
  Future<void> _stopSignIn() async {
    await _tokenSession?.dispose();
    _tokenSession = null;
    await client.disconnect();
  }

  Future<bool> _waitForRegistration() {
    final done = Completer<bool>();
    final sub = client.connectionEvents.listen((e) {
      if (done.isCompleted) return;
      if (e.registrationState == RegistrationState.registered) done.complete(true);
      if (e.registrationState == RegistrationState.failed) done.complete(false);
    });
    return done.future
        .timeout(const Duration(seconds: 20), onTimeout: () => isRegistered)
        .whenComplete(sub.cancel);
  }

  Future<void> signOut() async {
    await _unregisterForPush();
    await _tokenSession?.dispose();
    _tokenSession = null;
    await client.disconnect();
    await _clearSaved();
    notifyListeners();
  }

  void clearSignInError() {
    signInError = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Calls
  // ---------------------------------------------------------------------------

  /// Calls a phone number. What the user typed becomes E.164 first.
  Future<void> call(String input) async {
    final number = toE164(input, countryCode: AppConfig.defaultCountryCode);
    if (number == null) {
      _tell('Enter a phone number, such as +919876543210.');
      return;
    }
    notice = null;
    remoteParty = number;
    callDirection = CallDirection.outbound;
    _startCallService(outbound: true);
    try {
      await client.makeCall(number);
    } catch (e) {
      _stopCallService();
      _tell(_friendly(e));
    }
    notifyListeners();
  }

  Future<void> answer() async {
    // The user's tap: the moment Android lets the microphone service start.
    _startCallService(outbound: false);
    await _try(client.acceptCall);
  }

  Future<void> decline() => _try(client.rejectCall);

  Future<void> hangup() => _try(client.hangup);

  Future<void> toggleMute() async {
    await _try(() => muted ? client.unmute() : client.mute());
    muted = client.isMuted;
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    await _try(() => client.setSpeakerphone(!speakerOn));
    speakerOn = client.isSpeakerOn;
    notifyListeners();
  }

  /// Hold is a SIP re-INVITE: the other party hears Vobiz's hold music.
  Future<void> toggleHold() => _try(() => isHeld ? client.resume() : client.hold());

  /// Keypad presses for an IVR (DTMF).
  Future<void> sendDigits(String digits) => _try(() => client.sendDtmf(digits));

  /// Sends the other party to [to] (a phone number or a SIP user name) and
  /// ends this phone's side of the call. Done by the sample server with the
  /// Vobiz Transfer API, because it needs the Auth Token.
  Future<bool> transfer(String to) async {
    final uuid = client.callUuid;
    if (uuid == null) {
      _tell('Vobiz has not reported this call\'s ID yet. Try again in a moment.');
      return false;
    }
    final target = to.trim().startsWith(RegExp(r'[+\d]')) ? toE164(to, countryCode: AppConfig.defaultCountryCode) : to.trim();
    if (target == null || target.isEmpty) {
      _tell('Enter a phone number or a SIP user name to transfer to.');
      return false;
    }
    try {
      await backend.transfer(callUuid: uuid, to: target);
      _tell('Transferring to $target');
      return true;
    } on BackendException catch (e) {
      _tell('Transfer failed: ${e.message}');
      return false;
    }
  }

  void clearNotice() {
    notice = null;
    notifyListeners();
  }

  Future<void> _try(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _tell(_friendly(e));
    }
  }

  void _tell(String message) {
    notice = message;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // SDK events
  // ---------------------------------------------------------------------------

  void _onConnection(ConnectionEvent e) {
    connection = e;
    notifyListeners();
  }

  void _onError(ErrorEvent e) {
    if (signingIn) {
      signInError = e.message;
    } else if (hasCall) {
      notice = e.message;
    }
    notifyListeners();
  }

  void _onCall(CallEvent e) {
    final previous = callState;
    callState = e.state;
    callDirection = e.direction ?? callDirection;
    final who = e.remoteIdentity ?? '';
    if (who.isNotEmpty) remoteParty = displayParty(who);
    switch (e.state) {
      case CallStateStatus.incoming:
        if (previous != CallStateStatus.incoming) unawaited(_ringForCall(e));
      case CallStateStatus.active:
        connectedAt ??= DateTime.now();
        _closeRingingScreen();
      case CallStateStatus.ended:
      case CallStateStatus.failed:
        if (e.state == CallStateStatus.failed) {
          notice = 'Call failed: ${e.reason ?? e.message ?? 'unknown reason'}'
              '${e.sipCode == null ? '' : ' (SIP ${e.sipCode})'}';
        }
        _closeRingingScreen();
        _stopCallService();
        connectedAt = null;
        muted = false;
        speakerOn = false;
        callDirection = null;
      default:
        break;
    }
    notifyListeners();
  }

  /// A call rings here. A pushed call already has its call screen; any other
  /// gets one too, which rings and vibrates even with the app open.
  Future<void> _ringForCall(CallEvent e) async {
    final pushed = client.pushedCall;
    if (pushed != null && client.isPushedCall(e.callId)) {
      _ringingScreenId = pushed.callId;
      return;
    }
    final id = 'sip-${e.callId}';
    _ringingScreenId = id;
    await callScreen.showIncoming(
      id: id,
      caller: remoteParty,
      extra: <String, dynamic>{'source': 'sip'},
    );
  }

  void _closeRingingScreen() {
    final id = _ringingScreenId;
    _ringingScreenId = null;
    if (id == null) return;
    _closingScreens.add(id);
    unawaited(callScreen.end(id));
  }

  // ---------------------------------------------------------------------------
  // Vobiz push: a call to this phone while the app is closed
  // ---------------------------------------------------------------------------

  /// A push, from Android (any app state) or Firebase (app open). Vobiz holds
  /// the call for up to 30 s while the app signs in and claims it.
  void _onPushData(Map<String, String> data) {
    final p = VobizIncomingPush.tryParse(data);
    if (p == null) return;
    if (p.kind == VobizPushKind.callEnded) {
      _closingScreens.add(p.callId);
      unawaited(callScreen.end(p.callId));
      return;
    }
    if (!p.isHeldByVobiz || p.isTest || !_seenPushes.add(p.callId) || p.isExpired()) return;
    if (hasCall) {
      // On a call already: claim it anyway and the SDK turns it away (busy).
      client.handleIncomingPush(p);
      return;
    }
    unawaited(callScreen.showIncoming(
      id: p.callId,
      caller: _pushCaller(p),
      extra: <String, dynamic>{...data, 'source': 'vobiz'},
    ));
    client.handleIncomingPush(p);
    _signInForPush();
  }

  /// Signs in with the saved sign-in if a pushed call needs it.
  void _signInForPush() {
    final saved = _saved;
    if (client.isConnected || signingIn) return;
    if (saved == null) {
      _tell('A call came in, but there is no saved sign-in. Sign in with "Remember me" to take calls.');
      return;
    }
    unawaited(_signIn(saved, remember: true));
  }

  Future<void> _onCallScreenEvent(ck.CallEvent? event) async {
    switch (event) {
      case ck.CallEventActionCallAccept(:final callKitParams):
        final data = _stringMap(callKitParams.extra);
        if (data['source'] == 'vobiz') {
          final p = VobizIncomingPush.tryParse(data);
          if (p == null) return;
          _ringingScreenId = callKitParams.id;
          _startCallService(outbound: false, caller: _pushCaller(p));
          // Answers the call as soon as its INVITE arrives (now, if it rings).
          client.reportCallScreenAccepted(p);
          _signInForPush();
        } else if (isRingingIn) {
          await answer();
        }
      case ck.CallEventActionCallDecline(:final callKitParams):
        if (_closingScreens.remove(callKitParams.id)) return;
        final data = _stringMap(callKitParams.extra);
        if (data['source'] == 'vobiz') {
          final p = VobizIncomingPush.tryParse(data);
          if (p == null) return;
          // Vobiz cannot drop a held call without the claim, so the app still
          // signs in; the SDK then turns the call away and the caller hears busy.
          client.reportCallScreenDeclined(p);
          _signInForPush();
        } else if (isRingingIn) {
          await decline();
        }
      case ck.CallEventActionCallEnded(:final callKitParams):
        if (_closingScreens.remove(callKitParams.id)) return;
        if (isRingingIn) {
          await decline();
        } else if (hasCall) {
          await hangup();
        }
      case ck.CallEventActionCallTimeout(:final id):
        if (id == _ringingScreenId && isRingingIn) await decline();
      default:
        break;
    }
  }

  void _onPushCallUpdate(VobizPushCallUpdate update) {
    if (update.status != VobizPushCallStatus.expired) return;
    final id = update.push.callId;
    _closingScreens.add(id);
    unawaited(callScreen.end(id));
    if (!hasCall) _stopCallService();
    _tell('The call from ${_pushCaller(update.push)} ended before it reached this phone.');
  }

  static String _pushCaller(VobizIncomingPush p) =>
      p.caller.isNotEmpty ? displayParty(p.caller) : (p.callerNumber.isNotEmpty ? p.callerNumber : 'Unknown caller');

  static Map<String, Object?> _stringMap(Map<String, dynamic>? extra) =>
      <String, Object?>{for (final entry in (extra ?? const <String, dynamic>{}).entries) entry.key: '${entry.value}'};

  // ---------------------------------------------------------------------------
  // Registering this phone with Vobiz push
  // ---------------------------------------------------------------------------

  Future<void> _registerForPush() async {
    final user = client.sipUsername;
    if (user == null || !isRegistered) return;
    if (!push.available) {
      _setPush(PushReadiness.failed, push.problem ?? 'Firebase is not set up in this build.');
      return;
    }
    if (!backend.hasAppKey) {
      _setPush(PushReadiness.failed, 'Build with --dart-define=VOBIZ_APP_KEY=<the server\'s APP_KEY> to ring this phone when the app is closed.');
      return;
    }
    _setPush(PushReadiness.registering, 'Registering this phone with Vobiz push…');
    await push.requestNotificationPermission();
    final token = await push.token();
    if (token == null) {
      _setPush(PushReadiness.failed, 'Firebase gave no push token (no network, or no Google Play services).');
      return;
    }
    final info = await platform.appInfo();
    final devices = backend.pushDevices();
    try {
      await devices.register(VobizPushDevice(
        deviceId: await _installId(),
        pushToken: token,
        sipUsername: user,
        appBundleId: info.packageName,
        appVersion: info.version,
        sdkVersion: VobizClient.sdkVersion,
      ));
      _setPush(PushReadiness.ready, 'Calls to $user ring this phone, even with the app closed.');
    } catch (e) {
      _setPush(PushReadiness.failed, _friendly(e));
    }
  }

  Future<void> _unregisterForPush() async {
    if (pushReadiness == PushReadiness.off) return;
    _setPush(PushReadiness.off, '');
    try {
      await backend.pushDevices().logout(await _installId());
    } catch (_) {
      // Signing out goes ahead; Vobiz stops pushing when the token goes stale.
    }
  }

  void _setPush(PushReadiness readiness, String detail) {
    pushReadiness = readiness;
    pushDetail = detail;
    notifyListeners();
  }

  /// Android 14+: whether a call may show over the lock screen.
  Future<bool?> canUseFullScreen() => callScreen.canUseFullScreen();

  Future<void> openFullScreenSettings() => callScreen.requestFullScreen();

  // ---------------------------------------------------------------------------
  // The call's foreground service
  // ---------------------------------------------------------------------------

  void _startCallService({required bool outbound, String? caller}) {
    if (_callServiceRunning) return;
    _callServiceRunning = true;
    unawaited(platform.startCallService(caller: caller ?? remoteParty, outbound: outbound));
  }

  void _stopCallService() {
    if (!_callServiceRunning) return;
    _callServiceRunning = false;
    unawaited(platform.stopCallService());
  }

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------

  Future<SavedSignIn?> _readSaved() async {
    try {
      final mode = await _storage.read(key: _kMode);
      if (mode == SignInMode.accessToken.name) {
        final identity = await _storage.read(key: _kIdentity);
        return identity == null ? null : SavedSignIn.accessToken(identity: identity);
      }
      if (mode == SignInMode.endpoint.name) {
        final username = await _storage.read(key: _kUsername);
        final password = await _storage.read(key: _kPassword);
        return username == null || password == null ? null : SavedSignIn.endpoint(username: username, password: password);
      }
    } catch (_) {
      // Unreadable (for example after a restore to another phone): sign in again.
    }
    return null;
  }

  Future<void> _save(SavedSignIn signIn) async {
    await _clearSaved();
    await _storage.write(key: _kMode, value: signIn.mode.name);
    if (signIn.mode == SignInMode.endpoint) {
      await _storage.write(key: _kUsername, value: signIn.username);
      await _storage.write(key: _kPassword, value: signIn.password);
    } else {
      await _storage.write(key: _kIdentity, value: signIn.identity);
    }
    _saved = signIn;
  }

  Future<void> _clearSaved() async {
    for (final key in <String>[_kMode, _kUsername, _kPassword, _kIdentity]) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
    }
    _saved = null;
  }

  /// A random id for this install, kept for the push registration.
  Future<String> _installId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kInstallId);
    if (existing != null) return existing;
    final random = Random.secure();
    final id = List<String>.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString(_kInstallId, id);
    return id;
  }

  static String _friendly(Object error) {
    final text = switch (error) {
      VobizException(:final message) => message,
      BackendException(:final message) => message,
      ArgumentError(:final message) => '$message',
      StateError(:final message) => message,
      _ => '$error',
    };
    final lower = text.toLowerCase();
    if (lower.contains('403') || lower.contains('wrong credentials') || lower.contains('authentication failed')) {
      return 'Wrong username or password.';
    }
    return text;
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    unawaited(_tokenSession?.dispose());
    super.dispose();
  }
}
