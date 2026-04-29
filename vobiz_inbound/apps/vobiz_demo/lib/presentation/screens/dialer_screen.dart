import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../app.dart';
import '../../integration/dependency_injection.dart';
import '../../integration/sdk_factory.dart';
import '../../services/fcm_service.dart';
import '../viewmodels/call_view_model.dart';
import '../viewmodels/sdk_view_model.dart';
import '../widgets/vobiz_logo.dart';
import 'active_call_screen.dart';
import 'incoming_call_screen.dart';

class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  late final CallViewModel _callViewModel;
  late final TextEditingController _numberController;
  bool _initialized = false;
  bool _incomingDialogVisible = false;
  bool _callScreenVisible = false;
  StreamSubscription<Map<String, String>>? _foregroundCallSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;

    final SdkViewModel sdkViewModel = DependencyInjection.of(context);
    _callViewModel = CallViewModel(sdkViewModel.client);
    _numberController = TextEditingController();
    _callViewModel.addListener(_syncTextField);
    _foregroundCallSub =
        FcmService.foregroundInboundCalls.listen(_onForegroundInbound);
    _initialized = true;
  }

  @override
  void dispose() {
    _foregroundCallSub?.cancel();
    _callViewModel.removeListener(_syncTextField);
    _callViewModel.dispose();
    _numberController.dispose();
    super.dispose();
  }

  void _onForegroundInbound(Map<String, String> data) {
    if (!mounted || _incomingDialogVisible) return;
    final String caller = data['caller'] ?? 'Unknown';
    final String backendUrl =
        data['backend_url']?.isNotEmpty == true
            ? data['backend_url']!
            : SdkFactory.backendUrl;
    _incomingDialogVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => IncomingCallScreen(
        caller: caller,
        onAnswer: () async {
          Navigator.of(ctx).pop();
          FcmService.dismissCallNotification();
          final String callerId = SdkFactory.callerId;
          if (callerId.isNotEmpty) {
            await _callViewModel.client.makeCall(callerId);
          }
        },
        onReject: () async {
          Navigator.of(ctx).pop();
          try {
            await http.post(Uri.parse('$backendUrl/decline-inbound'));
          } catch (_) {}
        },
      ),
    ).whenComplete(() => _incomingDialogVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    final SdkViewModel sdkViewModel = DependencyInjection.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[sdkViewModel, _callViewModel]),
      builder: (BuildContext context, _) {
        _handleCallUiTransitions();

        final bool hasHeld = _callViewModel.hasHeldCall;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: const <Widget>[
                VobizLogo(width: 32),
                SizedBox(width: 10),
                Text(
                  'Dialer',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () async {
                  final NavigatorState nav = Navigator.of(context);
                  await sdkViewModel.disconnect();
                  if (!mounted) return;
                  nav.pop();
                },
                child: const Text('Logout'),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: <Widget>[
                    // Status row
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _StatusChip(
                            label: 'Network',
                            value: sdkViewModel.connectionEvent == null
                                ? 'Disconnected'
                                : sdkViewModel
                                    .connectionEvent!.connectionState.name,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatusChip(
                            label: 'SIP',
                            value: sdkViewModel.connectionEvent == null
                                ? '—'
                                : sdkViewModel
                                    .connectionEvent!.registrationState.name,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Call status panel
                    _InfoPanel(
                      title: 'Call Status',
                      body: _callViewModel.activeCall == null
                          ? 'No active call'
                          : '${_callViewModel.activeCall!.state.name}'
                              ' · ${_callViewModel.activeCall!.remoteIdentity}',
                    ),

                    if (hasHeld) ...<Widget>[
                      const SizedBox(height: 10),
                      _HeldCallPanel(
                        identity: _callViewModel.heldRemoteIdentity,
                        onResume: _callViewModel.resumeHeldCall,
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Number field
                    TextField(
                      controller: _numberController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        labelText: hasHeld
                            ? 'Enter number for second call'
                            : 'Enter Number',
                        hintText: '+1 (555) 000-0000',
                        prefixIcon: const Icon(Icons.dialpad_rounded),
                      ),
                      onChanged: _callViewModel.setDestination,
                    ),
                    const SizedBox(height: 16),

                    // Dial pad
                    _DialPad(
                      onKeyTap: _callViewModel.appendDigit,
                      onBackspace: _callViewModel.backspace,
                    ),
                    const SizedBox(height: 20),

                    // Call / Add Call button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _callViewModel.isBusy ||
                                !sdkViewModel.isConnected
                            ? null
                            : hasHeld
                                ? _callViewModel.addCallToConference
                                : _callViewModel.makeCall,
                        style: FilledButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 18),
                          backgroundColor: hasHeld
                              ? VobizDemoApp.kGreen
                              : VobizDemoApp.kOrange,
                        ),
                        icon: _callViewModel.isBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                hasHeld ? Icons.call_merge : Icons.call),
                        label: Text(
                          hasHeld ? 'Add Call' : 'Call',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // End all calls
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _callViewModel.canHangup
                            ? _callViewModel.hangup
                            : null,
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 18),
                          foregroundColor: VobizDemoApp.kRed,
                          side: BorderSide(
                            color: _callViewModel.canHangup
                                ? VobizDemoApp.kRed
                                : VobizDemoApp.kBorder,
                          ),
                        ),
                        icon: const Icon(Icons.call_end),
                        label: const Text(
                          'End All Calls',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    if (_callViewModel.errorMessage != null &&
                        _callViewModel.errorMessage!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 14),
                      Text(
                        _callViewModel.errorMessage!,
                        style:
                            const TextStyle(color: VobizDemoApp.kRed),
                        textAlign: TextAlign.center,
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

  void _syncTextField() {
    if (_numberController.text == _callViewModel.enteredNumber) return;
    _numberController.value = TextEditingValue(
      text: _callViewModel.enteredNumber,
      selection: TextSelection.collapsed(
        offset: _callViewModel.enteredNumber.length,
      ),
    );
  }

  Future<void> _showNumberDialog({
    required String title,
    required String hint,
    required String confirmLabel,
    required void Function(String) onConfirm,
  }) async {
    if (!mounted) return;
    final TextEditingController controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: VobizDemoApp.kSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: VobizDemoApp.kBorder),
        ),
        title: Text(title,
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onConfirm(controller.text.trim());
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    WidgetsBinding.instance
        .addPostFrameCallback((_) => controller.dispose());
  }

  void _handleCallUiTransitions() {
    final bool shouldShowIncomingPopup = _callViewModel.isIncomingRinging;
    final bool shouldShowCallScreen =
        _callViewModel.hasActiveCall && !_callViewModel.isIncomingRinging;

    if (shouldShowIncomingPopup && !_incomingDialogVisible) {
      _incomingDialogVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return IncomingCallScreen(
              caller: _callViewModel.remoteIdentity,
              onAnswer: () async {
                Navigator.of(dialogContext).pop();
                await _callViewModel.acceptIncomingCall();
              },
              onReject: () async {
                Navigator.of(dialogContext).pop();
                await _callViewModel.rejectIncomingCall();
              },
            );
          },
        );
        _incomingDialogVisible = false;
      });
    }

    if (_incomingDialogVisible && !shouldShowIncomingPopup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).maybePop();
      });
    }

    if (shouldShowCallScreen && !_callScreenVisible) {
      _callScreenVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AnimatedBuilder(
              animation: _callViewModel,
              builder: (BuildContext context, __) {
                final CallInfo? active = _callViewModel.activeCall;
                final bool isHeld = active?.isHeld ?? false;

                return ActiveCallScreen(
                  remoteIdentity: _callViewModel.remoteIdentity,
                  callState: active?.state.name ?? 'Call',
                  isMuted: _callViewModel.isMuted,
                  isHeld: isHeld,
                  canMerge: _callViewModel.canMerge,
                  heldRemoteIdentity: _callViewModel.hasHeldCall
                      ? _callViewModel.heldRemoteIdentity
                      : null,
                  onToggleMute: () => _callViewModel.toggleMute(),
                  onHold: isHeld
                      ? () => _callViewModel.resumeHeldCall()
                      : () => _callViewModel.holdActiveCall(),
                  onMerge: () => _callViewModel.mergeConference(),
                  onAddCall: () => _showNumberDialog(
                    title: 'Add Call',
                    hint: 'Number to add',
                    confirmLabel: 'Add',
                    onConfirm: (String number) =>
                        _callViewModel.addCallTo(number),
                  ),
                  onTransfer: () => _showNumberDialog(
                    title: 'Transfer Call',
                    hint: 'Transfer to number',
                    confirmLabel: 'Transfer',
                    onConfirm: (String number) =>
                        _callViewModel.transferCall(number),
                  ),
                  onHangup: () async {
                    final String? id = _callViewModel.activeCallId;
                    if (id != null) await _callViewModel.hangupCall(id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                );
              },
            ),
            fullscreenDialog: true,
          ),
        );
        _callScreenVisible = false;
      });
    }

    if (_callScreenVisible && !shouldShowCallScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).maybePop();
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Status chips
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: VobizDemoApp.kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VobizDemoApp.kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: VobizDemoApp.kMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info panel
// ---------------------------------------------------------------------------

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.title, required this.body});

  final String title;
  final String body;

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
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: VobizDemoApp.kOrange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: VobizDemoApp.kMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Held call panel
// ---------------------------------------------------------------------------

class _HeldCallPanel extends StatelessWidget {
  const _HeldCallPanel({
    required this.identity,
    required this.onResume,
  });

  final String identity;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1400),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VobizDemoApp.kOrange.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.pause_circle_outline,
              color: VobizDemoApp.kOrange, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'ON HOLD',
                  style: TextStyle(
                    color: VobizDemoApp.kOrange,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  identity.isEmpty ? 'Unknown' : identity,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onResume,
            style: FilledButton.styleFrom(
              backgroundColor: VobizDemoApp.kOrange,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Resume',
                style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dial pad
// ---------------------------------------------------------------------------

class _DialPad extends StatelessWidget {
  const _DialPad({required this.onKeyTap, required this.onBackspace});

  final ValueChanged<String> onKeyTap;
  final VoidCallback onBackspace;

  static const List<String> _keys = <String>[
    '1', '2', '3',
    '4', '5', '6',
    '7', '8', '9',
    '*', '0', '#',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.4,
          ),
          itemCount: _keys.length,
          itemBuilder: (BuildContext context, int index) {
            final String key = _keys[index];
            return Material(
              color: VobizDemoApp.kSurfaceHigh,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onKeyTap(key),
                child: Center(
                  child: Text(
                    key,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            onPressed: onBackspace,
            icon: const Icon(Icons.backspace_outlined,
                color: VobizDemoApp.kMuted),
          ),
        ),
      ],
    );
  }
}
