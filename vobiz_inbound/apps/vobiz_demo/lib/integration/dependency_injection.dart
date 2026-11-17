import 'package:flutter/widgets.dart';

import '../phone/phone_controller.dart';
import '../services/backend_api.dart';
import '../services/push/push_service.dart';
import 'app_config.dart';

/// Creates the app's one [PhoneController] (with its VobizClient) when the
/// app starts, before any screen, and hands it to the screens below.
class DependencyInjection extends StatefulWidget {
  const DependencyInjection({super.key, required this.push, required this.child, this.controller});

  final PushService push;
  final Widget child;

  /// Injected by tests; made here otherwise.
  final PhoneController? controller;

  static PhoneController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_Scope>();
    assert(scope != null, 'DependencyInjection not found in widget tree');
    return scope!.controller;
  }

  @override
  State<DependencyInjection> createState() => _DependencyInjectionState();
}

class _DependencyInjectionState extends State<DependencyInjection> {
  late final PhoneController _controller = widget.controller ??
      PhoneController(
        client: AppConfig.createClient(),
        backend: BackendApi(baseUrl: AppConfig.backendUrl, appKey: AppConfig.appKey),
        push: widget.push,
      );

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _controller.init();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Scope(controller: _controller, child: widget.child);
}

class _Scope extends InheritedWidget {
  const _Scope({required this.controller, required super.child});

  final PhoneController controller;

  @override
  bool updateShouldNotify(_Scope old) => old.controller != controller;
}
