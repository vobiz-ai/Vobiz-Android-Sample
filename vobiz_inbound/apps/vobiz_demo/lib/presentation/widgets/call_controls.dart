import 'package:flutter/material.dart';

import '../../app.dart';

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
                  ? VobizDemoApp.kOrange
                  : VobizDemoApp.kSurfaceHigh,
              foregroundColor: Colors.white,
            ),
            const SizedBox(width: 16),
            _ControlButton(
              icon: isHeld ? Icons.play_arrow : Icons.pause,
              label: isHeld ? 'Resume' : 'Hold',
              onPressed: onHold,
              backgroundColor: isHeld
                  ? VobizDemoApp.kOrange
                  : VobizDemoApp.kSurfaceHigh,
              foregroundColor: Colors.white,
            ),
            if (canMerge) ...<Widget>[
              const SizedBox(width: 16),
              _ControlButton(
                icon: Icons.call_merge,
                label: 'Merge',
                onPressed: onMerge,
                backgroundColor: VobizDemoApp.kGreen,
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
              backgroundColor: VobizDemoApp.kSurfaceHigh,
              foregroundColor: Colors.white,
            ),
            const SizedBox(width: 16),
            _ControlButton(
              icon: Icons.call_made,
              label: 'Transfer',
              onPressed: onTransfer,
              backgroundColor: VobizDemoApp.kSurfaceHigh,
              foregroundColor: Colors.white,
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Row 3: Hangup
        _ControlButton(
          icon: Icons.call_end,
          label: 'Hangup',
          onPressed: onHangup,
          backgroundColor: VobizDemoApp.kRed,
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
          width: 68,
          height: 68,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              disabledBackgroundColor:
                  VobizDemoApp.kSurface,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            child: Icon(icon, size: 26),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: VobizDemoApp.kMuted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
