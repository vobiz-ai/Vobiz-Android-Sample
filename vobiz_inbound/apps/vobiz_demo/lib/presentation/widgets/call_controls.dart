import 'package:flutter/material.dart';

/// Reusable controls shown on the active call screen.
///
/// Displays Mute, Hold, Merge (when a second call is held), and Hangup buttons.
class CallControls extends StatelessWidget {
  const CallControls({
    super.key,
    required this.isMuted,
    required this.isHeld,
    required this.canMerge,
    this.onToggleMute,
    this.onHold,
    this.onMerge,
    this.onHangup,
  });

  final bool isMuted;

  /// Whether the current call is held (shows Resume instead of Hold).
  final bool isHeld;

  /// Whether a second held call exists and merge is possible.
  final bool canMerge;

  final VoidCallback? onToggleMute;
  final VoidCallback? onHold;
  final VoidCallback? onMerge;
  final VoidCallback? onHangup;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // First row: Mute · Hold/Resume · Merge
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _ControlButton(
              icon: isMuted ? Icons.mic_off : Icons.mic,
              label: isMuted ? 'Unmute' : 'Mute',
              onPressed: onToggleMute,
              backgroundColor: isMuted
                  ? const Color(0xFF1E3A5F)
                  : const Color(0xFFE9EEF5),
              foregroundColor: isMuted ? Colors.white : Colors.black87,
            ),
            const SizedBox(width: 16),
            _ControlButton(
              icon: isHeld ? Icons.play_arrow : Icons.pause,
              label: isHeld ? 'Resume' : 'Hold',
              onPressed: onHold,
              backgroundColor: isHeld
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFE9EEF5),
              foregroundColor: isHeld ? Colors.white : Colors.black87,
            ),
            if (canMerge) ...<Widget>[
              const SizedBox(width: 16),
              _ControlButton(
                icon: Icons.call_merge,
                label: 'Merge',
                onPressed: onMerge,
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        // Second row: Hangup (centred, prominent)
        _ControlButton(
          icon: Icons.call_end,
          label: 'Hangup',
          onPressed: onHangup,
          backgroundColor: const Color(0xFFD92D20),
          foregroundColor: Colors.white,
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
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 72,
          height: 72,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              shape: const CircleBorder(),
            ),
            child: Icon(icon, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }
}
