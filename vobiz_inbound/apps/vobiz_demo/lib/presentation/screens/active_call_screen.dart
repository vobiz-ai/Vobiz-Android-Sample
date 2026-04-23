import 'package:flutter/material.dart';

import '../widgets/call_controls.dart';

/// Dedicated in-call screen shown while a call is ringing or active.
///
/// When a second call is held a banner appears at the top so the user can
/// see who is waiting and choose to merge or resume.
class ActiveCallScreen extends StatelessWidget {
  const ActiveCallScreen({
    super.key,
    required this.remoteIdentity,
    required this.callState,
    required this.isMuted,
    required this.isHeld,
    required this.canMerge,
    required this.onToggleMute,
    required this.onHold,
    required this.onMerge,
    required this.onHangup,
    this.heldRemoteIdentity,
  });

  final String remoteIdentity;
  final String callState;
  final bool isMuted;

  /// Whether this call is currently held (shows Resume instead of Hold).
  final bool isHeld;

  /// Whether a second held call exists (shows Merge button).
  final bool canMerge;

  final VoidCallback onToggleMute;
  final VoidCallback onHold;
  final VoidCallback onMerge;
  final VoidCallback onHangup;

  /// The identity of the person on hold, shown in the banner.
  final String? heldRemoteIdentity;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1728),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Call'),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Held-call banner — only visible when another call is on hold.
            if (heldRemoteIdentity != null && heldRemoteIdentity!.isNotEmpty)
              _HeldCallBanner(identity: heldRemoteIdentity!),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: <Widget>[
                    const Spacer(),

                    // Active-call avatar.
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: isHeld
                          ? const Color(0xFF78350F)
                          : const Color(0xFF1E293B),
                      child: Text(
                        remoteIdentity.isEmpty
                            ? '?'
                            : remoteIdentity[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 32,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      remoteIdentity.isEmpty ? 'Unknown' : remoteIdentity,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Text(
                      callState,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFFB6C2D2),
                      ),
                    ),

                    const Spacer(),

                    CallControls(
                      isMuted: isMuted,
                      isHeld: isHeld,
                      canMerge: canMerge,
                      onToggleMute: onToggleMute,
                      onHold: onHold,
                      onMerge: onMerge,
                      onHangup: onHangup,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact banner shown at the top of the active-call screen when a second
/// call is parked on hold.
class _HeldCallBanner extends StatelessWidget {
  const _HeldCallBanner({required this.identity});

  final String identity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF78350F),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: <Widget>[
          const Icon(Icons.pause_circle_outline, color: Colors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'On hold: $identity',
              style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
