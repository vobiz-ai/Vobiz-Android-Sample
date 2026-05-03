import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app.dart';
import '../../integration/dependency_injection.dart';
import '../../services/fcm_service.dart';
import '../viewmodels/sdk_view_model.dart';
import '../widgets/vobiz_logo.dart';
import 'dialer_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _secureStorage = FlutterSecureStorage();
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    _boot();
  }

  Future<void> _boot() async {
    final NavigatorState nav = Navigator.of(context);
    final SdkViewModel viewModel = DependencyInjection.of(context);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool rememberMe = prefs.getBool('vobiz_remember_me') ?? false;

    if (!rememberMe) {
      _goTo(nav, const LoginScreen());
      return;
    }

    final String? username = await _secureStorage.read(key: 'vobiz_username');
    final String? password = await _secureStorage.read(key: 'vobiz_password');

    if (username == null || password == null) {
      _goTo(nav, const LoginScreen());
      return;
    }

    // Check before login so the result is ready when we navigate.
    final bool fromAnswer = await FcmService.wasLaunchedFromAnswerAction();

    // Retry up to 3 times to handle transient server rate-limiting.
    bool success = false;
    for (int attempt = 0; attempt < 3 && !success; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 4));
        if (!mounted) return;
        viewModel.clearError();
      }
      success = await viewModel.login(username, password);
      if (!mounted) return;

      // Stop immediately on authentication errors — no point retrying.
      if (!success && _isAuthError(viewModel.errorMessage)) break;
    }

    if (!success) {
      final bool isAuthError = _isAuthError(viewModel.errorMessage);
      if (isAuthError) {
        // Credentials are wrong — wipe them so the user re-enters.
        await _secureStorage.delete(key: 'vobiz_username');
        await _secureStorage.delete(key: 'vobiz_password');
        await prefs.setBool('vobiz_remember_me', false);
        _goTo(
          nav,
          const LoginScreen(sessionExpiredMessage: 'Session expired. Please log in again.'),
        );
      } else {
        // Transient failure (server rate-limit, network) — keep credentials so
        // the user can retry immediately from a pre-filled login form.
        _goTo(nav, const LoginScreen());
      }
      return;
    }

    _goTo(nav, DialerScreen(autoAnswer: fromAnswer));
  }

  static bool _isAuthError(String? message) {
    if (message == null) return false;
    final lower = message.toLowerCase();
    return lower.contains('403') ||
        lower.contains('wrong credentials') ||
        lower.contains('authentication failed') ||
        lower.contains('forbidden');
  }

  void _goTo(NavigatorState nav, Widget screen) {
    if (!mounted) return;
    nav.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VobizDemoApp.kBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const <Widget>[
            VobizLogo(width: 56),
            SizedBox(height: 16),
            Text(
              'vobiz',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 48),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: VobizDemoApp.kOrange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
