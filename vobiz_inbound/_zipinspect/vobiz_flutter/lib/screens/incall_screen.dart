// lib/screens/incall_screen.dart

import 'package:flutter/material.dart';
import '../client/vobiz_client.dart';

class InCallScreen extends StatefulWidget {
  final VobizClient client;
  const InCallScreen({super.key, required this.client});

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  bool _showTransferPanel = false;
  bool _showAddCallPanel = false;
  final _transferController = TextEditingController();
  final _addCallController = TextEditingController();

  @override
  void dispose() {
    _transferController.dispose();
    _addCallController.dispose();
    super.dispose();
  }

  void _openTransferPanel() => setState(() {
        _showTransferPanel = true;
        _showAddCallPanel = false;
      });

  void _closeTransferPanel() {
    setState(() {
      _showTransferPanel = false;
      _transferController.clear();
    });
  }

  void _openAddCallPanel() => setState(() {
        _showAddCallPanel = true;
        _showTransferPanel = false;
      });

  void _closeAddCallPanel() {
    setState(() {
      _showAddCallPanel = false;
      _addCallController.clear();
    });
  }

  void _confirmAddCall() {
    final dest = _addCallController.text.trim();
    if (dest.isEmpty) return;
    _closeAddCallPanel();
    widget.client.addCall(dest);
  }

  void _confirmNewCall() {
    final dest = _addCallController.text.trim();
    if (dest.isEmpty) return;
    _closeAddCallPanel();
    widget.client.startSecondCall(dest);
  }

  void _confirmBlindTransfer() {
    final dest = _transferController.text.trim();
    if (dest.isEmpty) return;
    _closeTransferPanel();
    widget.client.transfer(dest);
  }

  void _confirmWarmTransfer() {
    final dest = _transferController.text.trim();
    if (dest.isEmpty) return;
    _closeTransferPanel();
    widget.client.warmTransferStart(dest);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VobizState>(
      stream: widget.client.stream,
      initialData: widget.client.state,
      builder: (context, snapshot) {
        final state            = snapshot.data!;
        final isHeld           = state.isHeld;
        final isMuted          = state.isMuted;
        final isTransfer       = state.call == CallState.transferring;
        final isWarmTransfer   = state.call == CallState.warmTransfer;
        final isConference     = state.isConference;
        final hasSecondCall    = state.hasSecondCall;
        final firstCallActive  = state.firstCallActive;
        final isLocked         = isTransfer || isWarmTransfer;
        final remote           = state.callerId ?? 'Unknown';

        // Auto-close panels when state locks or second call starts
        if ((isLocked || hasSecondCall) && (_showTransferPanel || _showAddCallPanel)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _showTransferPanel = false;
                _showAddCallPanel = false;
              });
            }
          });
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F1728),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: const Text('Call'),
            automaticallyImplyLeading: false,
          ),
          body: SafeArea(
            child: Column(
              children: [
                // ── Status banners ─────────────────────────────
                if (isHeld && !isLocked)
                  _Banner(
                    icon: Icons.pause_circle_outline,
                    iconColor: Colors.amber,
                    bgColor: const Color(0xFF78350F),
                    label: 'Call on hold',
                    labelColor: Colors.amber,
                  ),
                if (isTransfer)
                  _Banner(
                    icon: Icons.call_made,
                    iconColor: Colors.blue.shade300,
                    bgColor: const Color(0xFF1E3A5F),
                    label: 'Transferring call...',
                    labelColor: Colors.blue.shade200,
                  ),
                if (isWarmTransfer)
                  _Banner(
                    icon: Icons.people,
                    iconColor: Colors.green.shade300,
                    bgColor: const Color(0xFF14532D),
                    label: '3-way call — consulting transfer target',
                    labelColor: Colors.green.shade200,
                  ),
                if (isConference)
                  _Banner(
                    icon: Icons.group_add,
                    iconColor: Colors.teal.shade300,
                    bgColor: const Color(0xFF0F3D3D),
                    label: 'Conference — ${state.addedCallNumber ?? 'added party'} joined',
                    labelColor: Colors.teal.shade200,
                  ),
                if (hasSecondCall)
                  _Banner(
                    icon: firstCallActive ? Icons.looks_one : Icons.looks_two,
                    iconColor: Colors.orange.shade300,
                    bgColor: const Color(0xFF431407),
                    label: firstCallActive
                        ? 'Active: Call 1 · Call 2 on hold'
                        : 'Active: Call 2 · Call 1 on hold',
                    labelColor: Colors.orange.shade200,
                  ),

                // ── Body ───────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 32),

                        // Avatar
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: isWarmTransfer
                              ? const Color(0xFF14532D)
                              : isConference
                                  ? const Color(0xFF0F3D3D)
                                  : hasSecondCall
                                      ? const Color(0xFF431407)
                                      : isTransfer
                                          ? const Color(0xFF1E3A5F)
                                          : isHeld
                                              ? const Color(0xFF78350F)
                                              : const Color(0xFF1E293B),
                          child: Icon(
                            isWarmTransfer || isConference || hasSecondCall
                                ? Icons.people
                                : isTransfer
                                    ? Icons.call_made
                                    : Icons.person,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 20),

                        Text(
                          remote,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _statusText(state.call, isHeld,
                              isConference: isConference,
                              hasSecondCall: hasSecondCall,
                              firstCallActive: firstCallActive),
                          style: const TextStyle(
                              fontSize: 16, color: Color(0xFFB6C2D2)),
                        ),
                        const SizedBox(height: 40),

                        // ── Warm transfer controls ─────────────
                        if (isWarmTransfer) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: widget.client.warmTransferComplete,
                                  icon: const Icon(Icons.call_made, size: 20),
                                  label: const Text('Complete Transfer',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'You are in a 3-way call.\nTap "Complete Transfer" to hand off and leave.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Color(0xFFB6C2D2), fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          _CallButton(
                            icon: Icons.call_end,
                            label: 'Cancel & End',
                            color: Colors.red.shade700,
                            onTap: widget.client.hangup,
                          ),
                        ]

                        // ── Normal / blind-transfer controls ───
                        else ...[
                          // Control row: Mute · Hold · Transfer · Add
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _CallButton(
                                icon: isMuted ? Icons.mic_off : Icons.mic,
                                label: isMuted ? 'Unmute' : 'Mute',
                                color: isMuted
                                    ? Colors.blue.shade900
                                    : Colors.grey.shade800,
                                onTap: (isLocked || isHeld)
                                    ? null
                                    : () => isMuted
                                        ? widget.client.unmute()
                                        : widget.client.mute(),
                              ),
                              const SizedBox(width: 16),
                              _CallButton(
                                icon: isHeld ? Icons.play_arrow : Icons.pause,
                                label: isHeld ? 'Resume' : 'Hold',
                                color: isHeld
                                    ? Colors.amber.shade800
                                    : Colors.grey.shade800,
                                onTap: isLocked
                                    ? null
                                    : () => isHeld
                                        ? widget.client.resume()
                                        : widget.client.hold(),
                              ),
                              const SizedBox(width: 16),
                              _CallButton(
                                icon: Icons.call_made,
                                label: isTransfer ? 'Transferring' : 'Transfer',
                                color: _showTransferPanel
                                    ? Colors.indigo.shade700
                                    : Colors.grey.shade800,
                                onTap: isLocked
                                    ? null
                                    : () => _showTransferPanel
                                        ? _closeTransferPanel()
                                        : _openTransferPanel(),
                              ),
                              const SizedBox(width: 16),
                              _CallButton(
                                icon: isConference
                                    ? Icons.group_remove
                                    : hasSecondCall
                                        ? Icons.swap_calls
                                        : Icons.group_add,
                                label: isConference
                                    ? 'Remove'
                                    : hasSecondCall
                                        ? 'Swap'
                                        : 'Add Call',
                                color: isConference
                                    ? Colors.teal.shade700
                                    : hasSecondCall
                                        ? Colors.orange.shade800
                                        : _showAddCallPanel
                                            ? Colors.teal.shade800
                                            : Colors.grey.shade800,
                                onTap: isLocked || isHeld
                                    ? null
                                    : isConference
                                        ? widget.client.removeAddedCall
                                        : hasSecondCall
                                            ? widget.client.swapCalls
                                            : () => _showAddCallPanel
                                                ? _closeAddCallPanel()
                                                : _openAddCallPanel(),
                              ),
                            ],
                          ),

                          // ── Transfer input panel ─────────────
                          if (_showTransferPanel) ...[
                            const SizedBox(height: 28),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 28),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    controller: _transferController,
                                    autofocus: true,
                                    style: const TextStyle(color: Colors.white),
                                    keyboardType: TextInputType.text,
                                    textInputAction: TextInputAction.done,
                                    decoration: InputDecoration(
                                      hintText: '+91... or sip:user@domain',
                                      hintStyle: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 14),
                                      labelText: 'Transfer to',
                                      labelStyle: TextStyle(
                                          color: Colors.grey.shade400),
                                      filled: true,
                                      fillColor: const Color(0xFF1E293B),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      prefixIcon: const Icon(Icons.call_made,
                                          color: Colors.grey),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _TransferActionButton(
                                          icon: Icons.call_made,
                                          label: 'Transfer Now',
                                          subtitle: 'Blind',
                                          color: Colors.indigo.shade600,
                                          onTap: _confirmBlindTransfer,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _TransferActionButton(
                                          icon: Icons.people,
                                          label: 'Consult First',
                                          subtitle: 'Warm',
                                          color: Colors.green.shade700,
                                          onTap: _confirmWarmTransfer,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: _closeTransferPanel,
                                    child: Text('Cancel',
                                        style: TextStyle(
                                            color: Colors.grey.shade400)),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // ── Add call panel (Merge In / New Call) ─────
                          if (_showAddCallPanel) ...[
                            const SizedBox(height: 28),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    controller: _addCallController,
                                    autofocus: true,
                                    style: const TextStyle(color: Colors.white),
                                    keyboardType: TextInputType.text,
                                    textInputAction: TextInputAction.done,
                                    decoration: InputDecoration(
                                      hintText: '+91...',
                                      hintStyle: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 14),
                                      labelText: 'Number to add',
                                      labelStyle: TextStyle(
                                          color: Colors.grey.shade400),
                                      filled: true,
                                      fillColor: const Color(0xFF1E293B),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      prefixIcon: const Icon(Icons.group_add,
                                          color: Colors.grey),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _TransferActionButton(
                                          icon: Icons.people,
                                          label: 'Merge In',
                                          subtitle: 'Conference',
                                          color: Colors.teal.shade700,
                                          onTap: _confirmAddCall,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _TransferActionButton(
                                          icon: Icons.swap_calls,
                                          label: 'New Call',
                                          subtitle: 'Separate',
                                          color: Colors.orange.shade800,
                                          onTap: _confirmNewCall,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: _closeAddCallPanel,
                                    child: Text('Cancel',
                                        style: TextStyle(
                                            color: Colors.grey.shade400)),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // ── Second call controls (Option B) ──────────
                          if (hasSecondCall) ...[
                            const SizedBox(height: 20),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _CallSlot(
                                    label: 'Call 1',
                                    number: remote,
                                    isActive: firstCallActive,
                                  ),
                                  const SizedBox(height: 8),
                                  _CallSlot(
                                    label: 'Call 2',
                                    number: state.secondCallNumber ?? '...',
                                    isActive: !firstCallActive,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _TransferActionButton(
                                          icon: Icons.swap_calls,
                                          label: 'Swap',
                                          subtitle: 'Switch',
                                          color: Colors.orange.shade800,
                                          onTap: widget.client.swapCalls,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _TransferActionButton(
                                          icon: Icons.people,
                                          label: 'Merge',
                                          subtitle: 'Conference',
                                          color: Colors.teal.shade700,
                                          onTap: widget.client.mergeCalls,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _TransferActionButton(
                                          icon: Icons.call_end,
                                          label: 'End 2nd',
                                          subtitle: 'Resume 1st',
                                          color: Colors.red.shade700,
                                          onTap: widget.client.endSecondCall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 32),
                          _CallButton(
                            icon: Icons.call_end,
                            label: 'End Call',
                            color: Colors.red.shade700,
                            onTap: isTransfer
                                ? null
                                : widget.client.hangup,
                          ),
                        ],

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _statusText(CallState call, bool isHeld, {
    bool isConference = false,
    bool hasSecondCall = false,
    bool firstCallActive = true,
  }) {
    if (isHeld) return 'On hold';
    if (hasSecondCall) return firstCallActive ? 'Call 2 on hold' : 'Call 1 on hold';
    if (isConference) return 'Conference call';
    switch (call) {
      case CallState.calling:      return 'Calling...';
      case CallState.ringing:      return 'Ringing...';
      case CallState.inCall:       return 'In Call';
      case CallState.transferring: return 'Transferring...';
      case CallState.warmTransfer: return '3-way call';
      default:                     return '';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transfer action button (Blind / Warm)
// ─────────────────────────────────────────────────────────────────────────────

class _TransferActionButton extends StatelessWidget {
  const _TransferActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String   label;
  final String   subtitle;
  final Color    color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status banner
// ─────────────────────────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.label,
    required this.labelColor,
  });

  final IconData icon;
  final Color    iconColor;
  final Color    bgColor;
  final String   label;
  final Color    labelColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: labelColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Call slot card (Option B — shows active vs held call)
// ─────────────────────────────────────────────────────────────────────────────

class _CallSlot extends StatelessWidget {
  const _CallSlot({
    required this.label,
    required this.number,
    required this.isActive,
  });

  final String label;
  final String number;
  final bool   isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF1E3A2F)
            : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? Colors.green.shade700 : Colors.grey.shade700,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.call : Icons.pause,
            color: isActive ? Colors.green.shade400 : Colors.grey,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400)),
                Text(number,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ],
            ),
          ),
          Text(
            isActive ? 'ACTIVE' : 'ON HOLD',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.green.shade400 : Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable circular button
// ─────────────────────────────────────────────────────────────────────────────

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData      icon;
  final String        label;
  final Color         color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: onTap == null ? Colors.grey.shade900 : color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                color: onTap == null ? Colors.grey : Colors.white, size: 30),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  color: onTap == null ? Colors.grey : Colors.white70,
                  fontSize: 13)),
        ],
      ),
    );
  }
}
