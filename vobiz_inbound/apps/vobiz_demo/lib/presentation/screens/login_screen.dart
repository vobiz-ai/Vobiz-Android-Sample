import 'package:flutter/material.dart';

import '../../app.dart';
import '../../integration/dependency_injection.dart';
import '../viewmodels/sdk_view_model.dart';
import '../widgets/vobiz_logo.dart';
import 'dialer_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SdkViewModel viewModel = DependencyInjection.of(context);

    return AnimatedBuilder(
      animation: viewModel,
      builder: (BuildContext context, _) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Brand mark
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const VobizLogo(width: 44),
                          const SizedBox(width: 14),
                          const Text(
                            'vobiz',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 48),

                      // Login card
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Sign in',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Connect to the Vobiz signaling service.',
                                style: TextStyle(
                                  color: VobizDemoApp.kMuted,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: _usernameController,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (String? v) =>
                                    v == null || v.trim().isEmpty
                                        ? 'Username is required'
                                        : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: true,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: Icon(Icons.lock_outline),
                                ),
                                validator: (String? v) =>
                                    v == null || v.trim().isEmpty
                                        ? 'Password is required'
                                        : null,
                              ),
                              const SizedBox(height: 16),
                              _StatusPanel(
                                value: viewModel.connectionEvent == null
                                    ? 'Disconnected'
                                    : '${viewModel.connectionEvent!.connectionState.name}'
                                        ' / ${viewModel.connectionEvent!.registrationState.name}',
                                error: viewModel.errorMessage,
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: viewModel.isBusy
                                      ? null
                                      : () => _submit(viewModel),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                  ),
                                  child: viewModel.isBusy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Login',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
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

  Future<void> _submit(SdkViewModel viewModel) async {
    if (!_formKey.currentState!.validate()) return;

    final bool success = await viewModel.login(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
    );

    if (!mounted || !success) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DialerScreen()),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.value, this.error});

  final String value;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VobizDemoApp.kSurfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VobizDemoApp.kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Connection Status',
            style: TextStyle(
              color: VobizDemoApp.kMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (error != null && error!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              error!,
              style: const TextStyle(
                color: VobizDemoApp.kRed,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
