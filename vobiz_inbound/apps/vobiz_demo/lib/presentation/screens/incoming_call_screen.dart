import 'package:flutter/material.dart';

import '../../app.dart';

class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({
    super.key,
    required this.caller,
    required this.onAnswer,
    required this.onReject,
  });

  final String caller;
  final VoidCallback onAnswer;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: VobizDemoApp.kSurface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: VobizDemoApp.kBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Pulsing ring icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: VobizDemoApp.kGreen.withValues(alpha: 0.15),
                border: Border.all(
                    color: VobizDemoApp.kGreen.withValues(alpha: 0.4),
                    width: 2),
              ),
              child: const Icon(
                Icons.call,
                size: 32,
                color: VobizDemoApp.kGreen,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Incoming Call',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              caller.isEmpty ? 'Unknown caller' : caller,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: VobizDemoApp.kMuted,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.call_end),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: VobizDemoApp.kRed,
                      side: const BorderSide(color: VobizDemoApp.kRed),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAnswer,
                    icon: const Icon(Icons.call),
                    label: const Text('Answer'),
                    style: FilledButton.styleFrom(
                      backgroundColor: VobizDemoApp.kGreen,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
