import 'package:flutter/material.dart';

import '../../app.dart';

/// The call screen's buttons. Hold, keypad and transfer need a connected call.
class CallControls extends StatelessWidget {
  const CallControls({
    super.key,
    required this.connected,
    required this.muted,
    required this.speakerOn,
    required this.held,
    required this.onMute,
    required this.onSpeaker,
    required this.onHold,
    required this.onKeypad,
    required this.onTransfer,
    required this.onHangup,
  });

  final bool connected;
  final bool muted;
  final bool speakerOn;
  final bool held;
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
  final VoidCallback onHold;
  final VoidCallback onKeypad;
  final VoidCallback onTransfer;
  final VoidCallback onHangup;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _ControlButton(
              icon: muted ? Icons.mic_off : Icons.mic,
              label: muted ? 'Unmute' : 'Mute',
              active: muted,
              onPressed: onMute,
            ),
            _ControlButton(
              icon: speakerOn ? Icons.volume_up : Icons.volume_down,
              label: 'Speaker',
              active: speakerOn,
              onPressed: onSpeaker,
            ),
            _ControlButton(
              icon: held ? Icons.play_arrow : Icons.pause,
              label: held ? 'Resume' : 'Hold',
              active: held,
              onPressed: connected ? onHold : null,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _ControlButton(icon: Icons.dialpad, label: 'Keypad', onPressed: connected && !held ? onKeypad : null),
            _ControlButton(
              icon: Icons.call_end,
              label: 'Hang up',
              onPressed: onHangup,
              background: VobizDemoApp.kRed,
            ),
            _ControlButton(icon: Icons.phone_forwarded, label: 'Transfer', onPressed: connected ? onTransfer : null),
          ],
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.background,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 68,
          height: 68,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: background ?? (active ? VobizDemoApp.kOrange : VobizDemoApp.kSurfaceHigh),
              foregroundColor: Colors.white,
              disabledBackgroundColor: VobizDemoApp.kSurface,
              disabledForegroundColor: VobizDemoApp.kBorder,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            child: Icon(icon, size: 26, semanticLabel: label),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: VobizDemoApp.kMuted, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// A keypad for IVR menus: each press goes out as DTMF at once.
class KeypadSheet extends StatefulWidget {
  const KeypadSheet({super.key, required this.onDigit});

  final Future<void> Function(String digit) onDigit;

  @override
  State<KeypadSheet> createState() => _KeypadSheetState();
}

class _KeypadSheetState extends State<KeypadSheet> {
  String _sent = '';

  static const List<String> _keys = <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _sent.isEmpty ? 'Keypad' : _sent,
              style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 4, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.8,
              children: <Widget>[
                for (final String key in _keys)
                  Material(
                    color: VobizDemoApp.kSurfaceHigh,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() => _sent += key);
                        widget.onDigit(key);
                      },
                      child: Center(
                        child: Text(key,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
