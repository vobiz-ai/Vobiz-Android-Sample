import 'package:flutter/material.dart';

import '../../app.dart';
import '../../integration/dependency_injection.dart';
import '../../phone/phone_controller.dart';
import '../widgets/vobiz_logo.dart';
import 'dialer_screen.dart';
import 'login_screen.dart';

/// Shown while the PhoneController reads the saved sign-in. With one, the
/// controller is already signing in, so the dialer opens; without, the login.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  PhoneController? _controller;
  bool _routed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = DependencyInjection.of(context)..addListener(_route);
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  void _route() {
    final controller = _controller;
    if (_routed || !mounted || controller == null || !controller.initialized) return;
    _routed = true;
    final signedInOrSigningIn =
        controller.hasSavedSignIn || controller.signingIn || controller.isRegistered;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => signedInOrSigningIn ? const DialerScreen() : const LoginScreen(),
    ));
  }

  @override
  void dispose() {
    _controller?.removeListener(_route);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: VobizDemoApp.kBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            VobizLogo(width: 56),
            SizedBox(height: 16),
            Text(
              'vobiz',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
            ),
            SizedBox(height: 48),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: VobizDemoApp.kOrange),
            ),
          ],
        ),
      ),
    );
  }
}
