import 'package:flutter/material.dart';

import '../../app.dart';
import '../../integration/dependency_injection.dart';
import '../../phone/phone_controller.dart';
import '../widgets/vobiz_logo.dart';
import 'active_call_screen.dart';
import 'incoming_call_screen.dart';
import 'login_screen.dart';

/// The home screen once signed in: connection status, whether closed-app calls
/// work, and the dial pad. It opens the incoming-call dialog and the call
/// screen as the call's state changes.
class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  final TextEditingController _number = TextEditingController();
  PhoneController? _controller;
  Route<void>? _incomingDialog;
  bool _callScreenOpen = false;
  bool? _fullScreenAllowed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = DependencyInjection.of(context)..addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChange());
    _controller!.canUseFullScreen().then((bool? allowed) {
      if (mounted) setState(() => _fullScreenAllowed = allowed);
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChange);
    _number.dispose();
    super.dispose();
  }

  /// Opens and closes the incoming-call dialog and the call screen.
  void _onChange() {
    final c = _controller;
    if (c == null || !mounted) return;
    final navigator = Navigator.of(context);
    if (c.isRingingIn && _incomingDialog == null) {
      final dialog = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => ListenableBuilder(
          listenable: c,
          builder: (BuildContext context, _) => IncomingCallScreen(
            caller: c.remoteParty,
            onAnswer: c.answer,
            onReject: c.decline,
          ),
        ),
      );
      _incomingDialog = dialog;
      navigator.push(dialog).whenComplete(() {
        if (_incomingDialog == dialog) _incomingDialog = null;
      });
    } else if (!c.isRingingIn && _incomingDialog != null) {
      // Answered, declined, or the caller gave up. Removed by reference: the
      // call screen may already be on top of it.
      final dialog = _incomingDialog!;
      _incomingDialog = null;
      if (dialog.isActive) navigator.removeRoute(dialog);
    }
    if (c.hasCall && !c.isRingingIn && !_callScreenOpen) {
      _callScreenOpen = true;
      navigator
          .push(MaterialPageRoute<void>(builder: (_) => const ActiveCallScreen(), fullscreenDialog: true))
          .whenComplete(() => _callScreenOpen = false);
    }
  }

  Future<void> _signOut(PhoneController c) async {
    final navigator = Navigator.of(context);
    await c.signOut();
    if (!mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (Route<void> route) => false,
    );
  }

  void _backToLogin(PhoneController c) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => LoginScreen(message: c.signInError)),
      (Route<void> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = DependencyInjection.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (BuildContext context, _) {
        final event = c.connection;
        final failedSignIn = !c.signingIn && !c.isRegistered && c.signInError != null;
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                VobizLogo(width: 32),
                SizedBox(width: 10),
                Text('Dialer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              ],
            ),
            actions: <Widget>[TextButton(onPressed: () => _signOut(c), child: const Text('Sign out'))],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                            child: _StatusChip(
                                label: 'NETWORK', value: event?.connectionState.name ?? 'disconnected')),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _StatusChip(
                                label: 'SIP',
                                value: c.signingIn ? 'signing in' : (event?.registrationState.name ?? '—'))),
                        const SizedBox(width: 10),
                        Expanded(child: _StatusChip(label: 'CLOSED APP', value: _pushLabel(c.pushReadiness))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _InfoPanel(
                      title: 'SIGNED IN AS',
                      body: c.sipUsername ?? (c.savedSignIn?.label ?? '—'),
                      detail: c.pushDetail.isEmpty ? null : c.pushDetail,
                      accent: c.pushReadiness == PushReadiness.failed ? VobizDemoApp.kRed : VobizDemoApp.kOrange,
                    ),
                    if (_fullScreenAllowed == false) ...<Widget>[
                      const SizedBox(height: 10),
                      _HintPanel(
                        text: 'Allow full-screen calls so a call shows over the lock screen.',
                        action: 'Allow',
                        onTap: c.openFullScreenSettings,
                      ),
                    ],
                    if (failedSignIn) ...<Widget>[
                      const SizedBox(height: 10),
                      _HintPanel(
                        text: 'Sign-in failed: ${c.signInError}',
                        action: 'Sign in again',
                        onTap: () => _backToLogin(c),
                        color: VobizDemoApp.kRed,
                      ),
                    ],
                    const SizedBox(height: 20),
                    TextField(
                      controller: _number,
                      keyboardType: TextInputType.phone,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 1.5),
                      decoration: const InputDecoration(
                        labelText: 'Number to call',
                        hintText: '+91 98765 43210',
                        prefixIcon: Icon(Icons.dialpad_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _DialPad(
                      onKey: (String key) => _number.text += key,
                      onBackspace: () {
                        if (_number.text.isNotEmpty) {
                          _number.text = _number.text.substring(0, _number.text.length - 1);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: c.isRegistered && !c.hasCall ? () => c.call(_number.text) : null,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                      icon: const Icon(Icons.call),
                      label: const Text('Call', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    if (c.notice != null) ...<Widget>[
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: c.clearNotice,
                        child: Text(c.notice!,
                            textAlign: TextAlign.center, style: const TextStyle(color: VobizDemoApp.kMuted)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _pushLabel(PushReadiness r) => switch (r) {
        PushReadiness.ready => 'ready',
        PushReadiness.registering => 'registering',
        PushReadiness.failed => 'off (see below)',
        PushReadiness.off => 'off',
      };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: VobizDemoApp.kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VobizDemoApp.kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: const TextStyle(
                  color: VobizDemoApp.kMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.title, required this.body, this.detail, required this.accent});

  final String title;
  final String body;
  final String? detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VobizDemoApp.kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VobizDemoApp.kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(
                        color: VobizDemoApp.kMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                const SizedBox(height: 2),
                SelectableText(body,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(detail!, style: const TextStyle(color: VobizDemoApp.kMuted, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HintPanel extends StatelessWidget {
  const _HintPanel({required this.text, required this.action, required this.onTap, this.color = VobizDemoApp.kOrange});

  final String text;
  final String action;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13))),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }
}

class _DialPad extends StatelessWidget {
  const _DialPad({required this.onKey, required this.onBackspace});

  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;

  static const List<String> _keys = <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '0', '#'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.6,
          children: <Widget>[
            for (final String key in _keys)
              Material(
                color: VobizDemoApp.kSurfaceHigh,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onKey(key),
                  child: Center(
                    child: Text(key,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: 'Delete',
            onPressed: onBackspace,
            icon: const Icon(Icons.backspace_outlined, color: VobizDemoApp.kMuted),
          ),
        ),
      ],
    );
  }
}
