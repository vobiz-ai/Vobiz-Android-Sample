import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vobiz_webrtc/vobiz_webrtc.dart';

import '../../app.dart';
import '../../integration/dependency_injection.dart';
import '../../phone/phone_controller.dart';
import '../widgets/call_controls.dart';
import '../widgets/vobiz_logo.dart';

/// The call in progress: who, its state and length, and the controls. Closes
/// itself when the call ends.
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  PhoneController? _controller;
  Timer? _ticker;
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = DependencyInjection.of(context)..addListener(_closeWhenEnded);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  /// The call ended: close the keypad or transfer box if one is open, then
  /// this screen.
  void _closeWhenEnded() {
    final c = _controller;
    if (c == null || c.hasCall || _closing || !mounted) return;
    _closing = true;
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route == null) return;
    navigator.popUntil((Route<dynamic> r) => r == route);
    if (route.isCurrent) navigator.pop();
  }

  @override
  void dispose() {
    _controller?.removeListener(_closeWhenEnded);
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _showKeypad(PhoneController c) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: VobizDemoApp.kSurface,
        builder: (_) => KeypadSheet(onDigit: c.sendDigits),
      );

  Future<void> _showTransfer(PhoneController c) async {
    final target = await showDialog<String>(context: context, builder: (_) => const _TransferDialog());
    if (target != null && target.trim().isNotEmpty) await c.transfer(target);
  }

  @override
  Widget build(BuildContext context) {
    final c = DependencyInjection.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (BuildContext context, _) {
        final held = c.isHeld;
        return Scaffold(
          backgroundColor: VobizDemoApp.kBg,
          // The transfer box's keyboard floats over this screen instead of
          // squeezing it.
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                VobizLogo(width: 28),
                SizedBox(width: 10),
                Text('Call', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: <Widget>[
                  const Spacer(),
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: held ? const Color(0xFF1C1400) : VobizDemoApp.kSurface,
                      border: Border.all(color: held ? VobizDemoApp.kOrange : VobizDemoApp.kBorder, width: 2),
                    ),
                    child: Icon(
                      c.callDirection == CallDirection.inbound ? Icons.call_received : Icons.call_made,
                      size: 40,
                      color: held ? VobizDemoApp.kOrange : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    c.remoteParty.isEmpty ? 'Unknown' : c.remoteParty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: VobizDemoApp.kSurfaceHigh,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: VobizDemoApp.kBorder),
                    ),
                    child: Text(
                      _status(c),
                      style: TextStyle(
                        fontSize: 13,
                        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                        color: held ? VobizDemoApp.kOrange : VobizDemoApp.kMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (c.notice != null) ...<Widget>[
                    const SizedBox(height: 14),
                    Text(c.notice!, textAlign: TextAlign.center, style: const TextStyle(color: VobizDemoApp.kMuted)),
                  ],
                  const Spacer(),
                  CallControls(
                    connected: c.isConnected,
                    muted: c.muted,
                    speakerOn: c.speakerOn,
                    held: held,
                    onMute: c.toggleMute,
                    onSpeaker: c.toggleSpeaker,
                    onHold: c.toggleHold,
                    onKeypad: () => _showKeypad(c),
                    onTransfer: () => _showTransfer(c),
                    onHangup: c.hangup,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _status(PhoneController c) {
    final at = c.connectedAt;
    if (c.isHeld) return 'On hold';
    if (c.callState == CallStateStatus.active && at != null) {
      final d = DateTime.now().difference(at);
      final minutes = d.inMinutes.toString().padLeft(2, '0');
      final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '${d.inHours > 0 ? '${d.inHours}:' : ''}$minutes:$seconds';
    }
    return switch (c.callState) {
      CallStateStatus.connecting => 'Connecting…',
      CallStateStatus.ringing => 'Ringing…',
      CallStateStatus.incoming => 'Incoming call',
      _ => c.callState.name,
    };
  }
}

/// Asks where to transfer the other party. It owns its text controller, so the
/// controller lives until the box has finished closing.
class _TransferDialog extends StatefulWidget {
  const _TransferDialog();

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  final TextEditingController _to = TextEditingController();

  @override
  void dispose() {
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: VobizDemoApp.kSurface,
      title: const Text('Transfer call', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _to,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          labelText: 'Number or SIP user',
          hintText: '+91XXXXXXXXXX or alice',
          helperText: 'The other party goes there; your side of the call ends.',
          helperMaxLines: 2,
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_to.text), child: const Text('Transfer')),
      ],
    );
  }
}
