import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app.dart';
import '../../integration/dependency_injection.dart';
import '../viewmodels/sdk_view_model.dart';
import '../widgets/vobiz_logo.dart';
import 'dialer_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.sessionExpiredMessage});

  final String? sessionExpiredMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _rememberMeChecked = false;
  bool _showDebugInfo = false;
  String? _debugInfo;

  static const String _storageKeyUsername = 'vobiz_username';
  static const String _storageKeyPassword = 'vobiz_password';
  static const String _storageKeyRememberMe = 'vobiz_remember_me';

  static const _secureStorage = FlutterSecureStorage();

  Future<bool> _getRememberMeFlag() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_storageKeyRememberMe) ?? false;
  }

  Future<void> _saveCredentialsSecurely(String username, String password) async {
    await _secureStorage.write(key: _storageKeyUsername, value: username);
    await _secureStorage.write(key: _storageKeyPassword, value: password);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storageKeyRememberMe, true);
  }

  Future<void> _clearCredentials() async {
    await _secureStorage.delete(key: _storageKeyUsername);
    await _secureStorage.delete(key: _storageKeyPassword);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storageKeyRememberMe, false);
  }

  Future<void> _updateDebugInfo() async {
    final String? username = await _secureStorage.read(key: _storageKeyUsername);
    final String? password = await _secureStorage.read(key: _storageKeyPassword);
    final bool rememberMe = await _getRememberMeFlag();
    if (!mounted) return;
    setState(() {
      _debugInfo = '''Remember Me: $rememberMe
Username: ${username != null ? '***SAVED***' : 'Not saved'}
Password: ${password != null ? '***SAVED***' : 'Not saved'}''';
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit(SdkViewModel viewModel) async {
    if (!_formKey.currentState!.validate()) return;

    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();
    final NavigatorState nav = Navigator.of(context);

    final bool success = await viewModel.login(username, password);
    if (!mounted || !success) return;

    if (_rememberMeChecked) {
      await _saveCredentialsSecurely(username, password);
    }

    nav.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DialerScreen(autoAnswer: false)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SdkViewModel viewModel = DependencyInjection.of(context);

    return AnimatedBuilder(
      animation: viewModel,
      builder: (BuildContext context, _) {
        final String? errorToShow =
            viewModel.errorMessage ?? widget.sessionExpiredMessage;

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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const <Widget>[
                          VobizLogo(width: 44),
                          SizedBox(width: 14),
                          Text(
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
                              Row(
                                children: <Widget>[
                                  Checkbox(
                                    value: _rememberMeChecked,
                                    onChanged: (bool? value) {
                                      setState(() {
                                        _rememberMeChecked = value ?? false;
                                      });
                                    },
                                  ),
                                  const Expanded(
                                    child: Text(
                                      'Remember me on this device',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _StatusPanel(
                                value: viewModel.connectionEvent == null
                                    ? 'Disconnected'
                                    : '${viewModel.connectionEvent!.connectionState.name}'
                                        ' / ${viewModel.connectionEvent!.registrationState.name}',
                                error: errorToShow,
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
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () async {
                          setState(() => _showDebugInfo = !_showDebugInfo);
                          if (_showDebugInfo) await _updateDebugInfo();
                        },
                        child: const Text('🔍 Debug Info'),
                      ),
                      if (_showDebugInfo) ...<Widget>[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: VobizDemoApp.kSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: VobizDemoApp.kBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              SelectableText(
                                _debugInfo ?? 'Loading...',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  FilledButton.tonal(
                                    onPressed: _updateDebugInfo,
                                    child: const Text('Refresh'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.tonal(
                                    onPressed: () async {
                                      await _clearCredentials();
                                      await _updateDebugInfo();
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red.shade900,
                                    ),
                                    child: const Text('Clear Saved'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
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

// ─────────────────────────────────────────────────────────────────
// Status Panel Widget
// ─────────────────────────────────────────────────────────────────

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.value, required this.error});

  final String value;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final bool isError = error != null && error!.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isError
            ? Colors.red.shade900.withValues(alpha: 0.2)
            : Colors.blue.shade900.withValues(alpha: 0.2),
        border: Border.all(
          color: isError ? Colors.red.shade700 : Colors.blue.shade700,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isError ? error! : value,
        style: TextStyle(
          color: isError ? Colors.red.shade200 : Colors.blue.shade200,
          fontSize: 12,
        ),
      ),
    );
  }
}
