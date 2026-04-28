import 'package:flutter/material.dart';

import '../../app.dart';
import '../widgets/call_controls.dart';
import '../widgets/vobiz_logo.dart';

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
    required this.onAddCall,
    required this.onTransfer,
    required this.onHangup,
    this.heldRemoteIdentity,
  });

  final String remoteIdentity;
  final String callState;
  final bool isMuted;
  final bool isHeld;
  final bool canMerge;

  final VoidCallback onToggleMute;
  final VoidCallback onHold;
  final VoidCallback onMerge;
  final VoidCallback onAddCall;
  final VoidCallback onTransfer;
  final VoidCallback onHangup;

  final String? heldRemoteIdentity;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VobizDemoApp.kBg,
      appBar: AppBar(
        backgroundColor: VobizDemoApp.kBg,
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const <Widget>[
            VobizLogo(width: 28),
            SizedBox(width: 10),
            Text(
              'Active Call',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Held-call banner
            if (heldRemoteIdentity != null && heldRemoteIdentity!.isNotEmpty)
              _HeldCallBanner(identity: heldRemoteIdentity!),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: <Widget>[
                    const Spacer(),

                    // Avatar
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isHeld
                            ? const Color(0xFF1C1400)
                            : VobizDemoApp.kSurface,
                        border: Border.all(
                          color: isHeld
                              ? VobizDemoApp.kOrange
                              : VobizDemoApp.kBorder,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          remoteIdentity.isEmpty
                              ? '?'
                              : remoteIdentity[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: isHeld
                                ? VobizDemoApp.kOrange
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      remoteIdentity.isEmpty ? 'Unknown' : remoteIdentity,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: VobizDemoApp.kSurfaceHigh,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: VobizDemoApp.kBorder),
                      ),
                      child: Text(
                        isHeld ? 'On Hold' : callState,
                        style: TextStyle(
                          fontSize: 13,
                          color: isHeld
                              ? VobizDemoApp.kOrange
                              : VobizDemoApp.kMuted,
                          fontWeight: FontWeight.w600,
                        ),
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
                      onAddCall: onAddCall,
                      onTransfer: onTransfer,
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

class _HeldCallBanner extends StatelessWidget {
  const _HeldCallBanner({required this.identity});

  final String identity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1C1400),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: <Widget>[
          const Icon(Icons.pause_circle_outline,
              color: VobizDemoApp.kOrange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'On hold: $identity',
              style: const TextStyle(
                color: VobizDemoApp.kOrange,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
