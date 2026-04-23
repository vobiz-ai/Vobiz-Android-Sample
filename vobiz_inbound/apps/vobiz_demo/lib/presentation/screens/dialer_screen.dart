import 'package:flutter/material.dart';

import '../../integration/dependency_injection.dart';
import '../viewmodels/call_view_model.dart';
import '../viewmodels/sdk_view_model.dart';
import 'active_call_screen.dart';
import 'incoming_call_screen.dart';

/// Second screen of the demo app.
///
/// Handles the full multi-call flow:
///   - outbound calls via the dialpad
///   - "Add Call" when a call is already held (second leg for conference)
///   - hold / resume / merge controls forwarded from [ActiveCallScreen]
///   - incoming call popup (unchanged)
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;

    final SdkViewModel sdkViewModel =
        DependencyInjection.of(context).sdkViewModel;
    _callViewModel = CallViewModel(sdkViewModel.client);
    _numberController = TextEditingController();
    _callViewModel.addListener(_syncTextField);
    _initialized = true;
  }

  @override
  void dispose() {
    _callViewModel.removeListener(_syncTextField);
    _callViewModel.dispose();
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SdkViewModel sdkViewModel =
        DependencyInjection.of(context).sdkViewModel;

    return AnimatedBuilder(
      animation:
          Listenable.merge(<Listenable>[sdkViewModel, _callViewModel]),
      builder: (BuildContext context, _) {
        _handleCallUiTransitions();

        final bool hasHeld = _callViewModel.hasHeldCall;

        return Scaffold(
          backgroundColor: const Color(0xFFF3F5F8),
          appBar: AppBar(
            title: const Text('Dialer'),
            actions: <Widget>[
              TextButton(
                onPressed: () async {
                  await sdkViewModel.disconnect();
                  if (!mounted) return;
                  Navigator.of(context).pop();
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
                  padding: const EdgeInsets.all(24),
                  children: <Widget>[
                    _InfoPanel(
                      title: 'SDK Connection',
                      body: sdkViewModel.connectionEvent == null
                          ? 'Disconnected'
                          : '${sdkViewModel.connectionEvent!.connectionState.name} / '
                              '${sdkViewModel.connectionEvent!.registrationState.name}',
                    ),
                    const SizedBox(height: 8),
                    _InfoPanel(
                      title: 'Call Status',
                      body: _callViewModel.activeCall == null
                          ? 'No active call'
                          : '${_callViewModel.activeCall!.state.name}'
                              ' | ${_callViewModel.activeCall!.remoteIdentity}',
                    ),

                    // Held-call info panel — visible when a call is parked.
                    if (hasHeld) ...<Widget>[
                      const SizedBox(height: 8),
                      _HeldCallPanel(
                        identity: _callViewModel.heldRemoteIdentity,
                        onResume: _callViewModel.resumeHeldCall,
                      ),
                    ],

                    const SizedBox(height: 16),

                    TextField(
                      controller: _numberController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: hasHeld
                            ? 'Enter number for second call'
                            : 'Enter Number',
                        hintText: 'Destination number',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.dialpad_rounded),
                      ),
                      onChanged: _callViewModel.setDestination,
                    ),
                    const SizedBox(height: 20),
                    _DialPad(
                      onKeyTap: _callViewModel.appendDigit,
                      onBackspace: _callViewModel.backspace,
                    ),
                    const SizedBox(height: 20),

                    // Primary call button — changes to "Add Call" when a call is held.
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _callViewModel.isBusy ||
                                !sdkViewModel.isConnected
                            ? null
                            : hasHeld
                                ? _callViewModel.addCallToConference
                                : _callViewModel.makeCall,
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
                                hasHeld ? Icons.call_merge : Icons.call,
                              ),
                        label: Text(hasHeld ? 'Add Call' : 'Call'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          backgroundColor:
                              hasHeld ? const Color(0xFF16A34A) : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _callViewModel.canHangup
                            ? _callViewModel.hangup
                            : null,
                        icon: const Icon(Icons.call_end),
                        label: const Text('End All Calls'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                      ),
                    ),

                    if (_callViewModel.errorMessage != null &&
                        _callViewModel.errorMessage!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(
                        _callViewModel.errorMessage!,
                        style: const TextStyle(color: Colors.red),
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
// Info panels
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E7ED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

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
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.pause_circle_outline,
              color: Color(0xFFB45309), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'On Hold',
                  style: TextStyle(
                    color: Colors.amber.shade900,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  identity.isEmpty ? 'Unknown' : identity,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onResume,
            child: const Text('Resume'),
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
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.15,
          ),
          itemCount: _keys.length,
          itemBuilder: (BuildContext context, int index) {
            final String key = _keys[index];
            return FilledButton.tonal(
              onPressed: () => onKeyTap(key),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(
                key,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton.filledTonal(
            onPressed: onBackspace,
            icon: const Icon(Icons.backspace_outlined),
          ),
        ),
      ],
    );
  }
}
