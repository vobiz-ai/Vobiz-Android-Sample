import 'package:flutter/material.dart';

/// Reusable controls shown on the active call screen.
///
/// Displays Mute, Hold, Add Call, Transfer, Merge (when held), and Hangup.
class CallControls extends StatelessWidget {
  const CallControls({
    super.key,
    required this.isMuted,
    required this.isHeld,
    required this.canMerge,
    this.onToggleMute,
    this.onHold,
    this.onMerge,
    this.onAddCall,
    this.onTransfer,
    this.onHangup,
  });

  final bool isMuted;
  final bool isHeld;
  final bool canMerge;

  final VoidCallback? onToggleMute;
  final VoidCallback? onHold;
  final VoidCallback? onMerge;
  final VoidCallback? onAddCall;
  final VoidCallback? onTransfer;
  final VoidCallback? onHangup;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Row 1: Mute · Hold/Resume · Merge
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
        const SizedBox(height: 16),
        // Row 2: Add Call · Transfer
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _ControlButton(
              icon: Icons.add_call,
              label: 'Add Call',
              onPressed: onAddCall,
              backgroundColor: const Color(0xFFE9EEF5),
              foregroundColor: Colors.black87,
            ),
            const SizedBox(width: 16),
            _ControlButton(
              icon: Icons.call_made,
              label: 'Transfer',
              onPressed: onTransfer,
              backgroundColor: const Color(0xFFE9EEF5),
              foregroundColor: Colors.black87,
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Row 3: Hangup
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
