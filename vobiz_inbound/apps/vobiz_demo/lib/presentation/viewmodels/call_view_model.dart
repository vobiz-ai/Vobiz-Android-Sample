import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vobiz_webrtc/vobiz_webrtc.dart';

/// Snapshot of a single call leg for UI consumption.
class CallInfo {
  const CallInfo({
    required this.callId,
    required this.remoteIdentity,
    required this.state,
    required this.isMuted,
  });

  final String callId;
  final String remoteIdentity;
  final CallStateStatus state;
  final bool isMuted;

  bool get isActive => state == CallStateStatus.active;
  bool get isHeld => state == CallStateStatus.held;
  bool get isConnecting =>
      state == CallStateStatus.connecting ||
      state == CallStateStatus.ringing;
}

/// View model for the dialer screen.
///
/// Tracks up to two simultaneous call legs — one active and one held — and
/// exposes all actions needed for hold, add-call, and conference merge.
class CallViewModel extends ChangeNotifier {
  CallViewModel(this.client) {
    _callSub = client.callEvents.listen(_onCallEvent);
    _errorSub = client.errorEvents.listen((ErrorEvent event) {
      errorMessage = event.message;
      notifyListeners();
    });
  }

  final VobizClient client;

  StreamSubscription<CallEvent>? _callSub;
  StreamSubscription<ErrorEvent>? _errorSub;

  // Per-call state keyed by callId.
  final Map<String, CallInfo> _calls = <String, CallInfo>{};

  // Dialer input.
  String destination = '';

  // Busy flag while an async operation is running.
  bool isBusy = false;

  String? errorMessage;

  // -------------------------------------------------------------------------
  // Derived state exposed to the UI
  // -------------------------------------------------------------------------

  /// The currently active (non-held) call, if any.
  CallInfo? get activeCall {
    for (final CallInfo info in _calls.values) {
      if (info.isActive || info.isConnecting) return info;
    }
    return null;
  }

  /// The currently held call, if any.
  CallInfo? get heldCall {
    for (final CallInfo info in _calls.values) {
      if (info.isHeld) return info;
    }
    return null;
  }

  /// All live (non-ended) calls.
  Iterable<CallInfo> get liveCalls =>
      _calls.values.where((CallInfo c) => c.isActive || c.isHeld || c.isConnecting);

  bool get hasActiveCall => activeCall != null;
  bool get hasHeldCall => heldCall != null;
  bool get canMerge => hasActiveCall && hasHeldCall;

  /// Convenience getters used by the dialer / active-call screens.
  String? get activeCallId => activeCall?.callId;
  String? get heldCallId => heldCall?.callId;

  bool get isMuted => activeCall?.isMuted ?? false;
  bool get canHangup =>
      activeCall != null || heldCall != null || _incomingCall != null;

  String get remoteIdentity =>
      activeCall?.remoteIdentity ?? destination.trim();
  String get heldRemoteIdentity => heldCall?.remoteIdentity ?? '';

  // Tracks which call (if any) is ringing inbound.
  CallInfo? get _incomingCall {
    for (final CallInfo info in _calls.values) {
      if (info.state == CallStateStatus.incoming ||
          (info.state == CallStateStatus.ringing &&
              _isIncomingCallId(info.callId))) {
        return info;
      }
    }
    return null;
  }

  bool isIncomingRinging = false;
  CallEvent? latestCallEvent;

  // Track which call IDs came from inbound (incoming) legs.
  final Set<String> _incomingCallIds = <String>{};

  bool _isIncomingCallId(String callId) => _incomingCallIds.contains(callId);

  // -------------------------------------------------------------------------
  // Dialer helpers
  // -------------------------------------------------------------------------

  String get enteredNumber => destination;

  bool get canCall => !isBusy && destination.trim().isNotEmpty;

  void setDestination(String value) {
    destination = value;
    notifyListeners();
  }

  void appendDigit(String value) {
    destination = '$destination$value';
    notifyListeners();
  }

  void backspace() {
    if (destination.isEmpty) return;
    destination = destination.substring(0, destination.length - 1);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Call actions
  // -------------------------------------------------------------------------

  /// Places a fresh outbound call (no existing call on hold).
  Future<void> makeCall() async {
    if (destination.trim().isEmpty) {
      errorMessage = 'Enter a number before placing a call.';
      notifyListeners();
      return;
    }

    isBusy = true;
    errorMessage = null;
    notifyListeners();

    try {
      await client.makeCall(destination.trim());
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Holds the active call then dials [destination] as a second leg.
  Future<void> addCallToConference() async {
    if (destination.trim().isEmpty) {
      errorMessage = 'Enter a number for the second call.';
      notifyListeners();
      return;
    }

    isBusy = true;
    errorMessage = null;
    notifyListeners();

    try {
      await client.addCall(destination.trim());
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Hangs up every live call leg.
  Future<void> hangup() async {
    final List<String> ids = _calls.keys.toList();
    for (final String id in ids) {
      await client.hangup(id);
    }
  }

  /// Hangs up a specific call leg.
  Future<void> hangupCall(String callId) async {
    await client.hangup(callId);
  }

  /// Holds the active call.
  Future<void> holdActiveCall() async {
    final String? id = activeCallId;
    if (id == null) return;
    errorMessage = null;
    notifyListeners();
    try {
      await client.hold(id);
    } catch (error) {
      errorMessage = error.toString();
      notifyListeners();
    }
  }

  /// Resumes the held call (swaps it back to active).
  Future<void> resumeHeldCall() async {
    final String? id = heldCallId;
    if (id == null) return;
    errorMessage = null;
    notifyListeners();
    try {
      await client.resume(id);
    } catch (error) {
      errorMessage = error.toString();
      notifyListeners();
    }
  }

  /// Merges the active and held calls into a conference.
  Future<void> mergeConference() async {
    final String? a = activeCallId;
    final String? h = heldCallId;
    if (a == null || h == null) return;

    isBusy = true;
    errorMessage = null;
    notifyListeners();

    try {
      await client.mergeConference(a, h);
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Toggles mute on the active call.
  Future<void> toggleMute() async {
    final String? id = activeCallId;
    if (id == null) return;
    try {
      if (isMuted) {
        await client.unmute(id);
      } else {
        await client.mute(id);
      }
    } catch (error) {
      errorMessage = error.toString();
      notifyListeners();
    }
  }

  // Inbound call helpers (used by DialerScreen).
  Future<void> acceptIncomingCall() async {
    final String? id = _incomingCall?.callId;
    errorMessage = null;
    notifyListeners();
    try {
      await client.acceptCall(id);
      isIncomingRinging = false;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> rejectIncomingCall() async {
    final String? id = _incomingCall?.callId;
    errorMessage = null;
    notifyListeners();
    try {
      await client.rejectCall(id);
      isIncomingRinging = false;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      notifyListeners();
    }
  }

  // -------------------------------------------------------------------------
  // Event handling
  // -------------------------------------------------------------------------

  void _onCallEvent(CallEvent event) {
    latestCallEvent = event;

    // Track inbound call IDs so we can distinguish them from outbound legs.
    final dynamic session = event.session;
    final bool incoming = session?.isIncoming as bool? ?? false;
    if (incoming) _incomingCallIds.add(event.callId);

    final String? muted =
        (session?.muted as bool? ?? false) ? 'true' : null;

    if (event.state == CallStateStatus.ended ||
        event.state == CallStateStatus.failed) {
      _calls.remove(event.callId);
      _incomingCallIds.remove(event.callId);
    } else {
      _calls[event.callId] = CallInfo(
        callId: event.callId,
        remoteIdentity: (session?.remoteIdentity as String?)?.isNotEmpty == true
            ? session!.remoteIdentity as String
            : destination.trim(),
        state: event.state,
        isMuted: muted != null,
      );
    }

    // Update inbound-ringing flag.
    isIncomingRinging = _calls.values.any(
      (CallInfo c) =>
          _incomingCallIds.contains(c.callId) &&
          (c.state == CallStateStatus.incoming ||
              c.state == CallStateStatus.ringing),
    );

    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  @override
  void dispose() {
    _callSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}
