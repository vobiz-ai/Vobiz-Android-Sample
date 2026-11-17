import 'package:flutter/material.dart';

import '../../app.dart';
import '../../integration/dependency_injection.dart';
import '../../phone/phone_controller.dart';
import '../widgets/vobiz_logo.dart';
import 'dialer_screen.dart';

/// Sign in as a SIP endpoint (username and password from the Vobiz Console),
/// or with an access token the sample server mints for an identity.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.message});

  /// Shown above the form, for example why the last sign-in ended.
  final String? message;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _identity = TextEditingController();
  SignInMode _mode = SignInMode.endpoint;
  bool _remember = true;
  bool _passwordVisible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final saved = DependencyInjection.of(context).savedSignIn;
    if (saved != null && _username.text.isEmpty && _identity.text.isEmpty) {
      _mode = saved.mode;
      _username.text = saved.username ?? '';
      _identity.text = saved.identity ?? '';
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _identity.dispose();
    super.dispose();
  }

  Future<void> _submit(PhoneController controller) async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final ok = _mode == SignInMode.endpoint
        ? await controller.signInWithEndpoint(
            username: _username.text, password: _password.text, remember: _remember)
        : await controller.signInWithAccessToken(identity: _identity.text, remember: _remember);
    if (!ok || !mounted) return;
    navigator.pushReplacement(MaterialPageRoute<void>(builder: (_) => const DialerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final controller = DependencyInjection.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final error = controller.signInError ?? widget.message;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          VobizLogo(width: 44),
                          SizedBox(width: 14),
                          Text('vobiz',
                              style: TextStyle(
                                  fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
                        ],
                      ),
                      const SizedBox(height: 40),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: VobizDemoApp.kSurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: VobizDemoApp.kBorder),
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const Text('Sign in',
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                              const SizedBox(height: 6),
                              Text(
                                _mode == SignInMode.endpoint
                                    ? 'A SIP endpoint from Vobiz Console → Voice → Endpoints.'
                                    : 'The sample server signs you in with a short-lived access token.',
                                style: const TextStyle(color: VobizDemoApp.kMuted, fontSize: 14),
                              ),
                              const SizedBox(height: 20),
                              SegmentedButton<SignInMode>(
                                segments: const <ButtonSegment<SignInMode>>[
                                  ButtonSegment<SignInMode>(
                                      value: SignInMode.endpoint, label: Text('SIP endpoint'), icon: Icon(Icons.dialpad)),
                                  ButtonSegment<SignInMode>(
                                      value: SignInMode.accessToken, label: Text('Access token'), icon: Icon(Icons.key)),
                                ],
                                selected: <SignInMode>{_mode},
                                onSelectionChanged: controller.signingIn
                                    ? null
                                    : (Set<SignInMode> s) {
                                        controller.clearSignInError();
                                        setState(() => _mode = s.first);
                                      },
                              ),
                              const SizedBox(height: 20),
                              if (_mode == SignInMode.endpoint) ...<Widget>[
                                TextFormField(
                                  controller: _username,
                                  style: const TextStyle(color: Colors.white),
                                  autocorrect: false,
                                  decoration: const InputDecoration(
                                      labelText: 'Endpoint username', prefixIcon: Icon(Icons.person_outline)),
                                  validator: (String? v) =>
                                      v == null || v.trim().isEmpty ? 'Enter the endpoint username' : null,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _password,
                                  obscureText: !_passwordVisible,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: 'Endpoint password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                                      icon: Icon(_passwordVisible ? Icons.visibility_off : Icons.visibility),
                                      onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                                    ),
                                  ),
                                  validator: (String? v) => v == null || v.isEmpty ? 'Enter the endpoint password' : null,
                                ),
                              ] else
                                TextFormField(
                                  controller: _identity,
                                  style: const TextStyle(color: Colors.white),
                                  autocorrect: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Identity',
                                    hintText: 'alice',
                                    helperText: 'Letters, digits, _ or -. You register as <identity>_<Auth ID>.',
                                    helperMaxLines: 2,
                                    prefixIcon: Icon(Icons.badge_outlined),
                                  ),
                                  validator: (String? v) => v != null && RegExp(r'^[A-Za-z0-9_-]{1,50}$').hasMatch(v.trim())
                                      ? null
                                      : 'Use 1 to 50 letters, digits, _ or -',
                                ),
                              const SizedBox(height: 8),
                              CheckboxListTile(
                                value: _remember,
                                onChanged: (bool? v) => setState(() => _remember = v ?? false),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity: ListTileControlAffinity.leading,
                                title: const Text('Remember me', style: TextStyle(color: Colors.white, fontSize: 14)),
                                subtitle: const Text(
                                  'Needed to take calls while the app is closed.',
                                  style: TextStyle(color: VobizDemoApp.kMuted, fontSize: 12),
                                ),
                              ),
                              if (error != null && error.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 8),
                                _ErrorPanel(message: error),
                              ],
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: controller.signingIn ? null : () => _submit(controller),
                                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                                child: controller.signingIn
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Sign in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: VobizDemoApp.kRed.withValues(alpha: 0.12),
        border: Border.all(color: VobizDemoApp.kRed.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFFFDA29B), fontSize: 13)),
    );
  }
}
