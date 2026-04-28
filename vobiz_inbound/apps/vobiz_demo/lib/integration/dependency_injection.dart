import 'package:flutter/widgets.dart';

import '../presentation/viewmodels/sdk_view_model.dart';
import 'sdk_factory.dart';

/// Provides [SdkViewModel] to the widget tree.
///
/// Uses a StatefulWidget + private InheritedWidget pair so the view model is
/// created exactly once (in initState) and disposed when the subtree is removed.
class DependencyInjection extends StatefulWidget {
  const DependencyInjection({super.key, required this.child});

  final Widget child;

  static SdkViewModel of(BuildContext context) {
    final _DependencyInjectionScope? scope =
        context.dependOnInheritedWidgetOfExactType<_DependencyInjectionScope>();
    assert(scope != null, 'DependencyInjection not found in widget tree');
    return scope!.sdkViewModel;
  }

  @override
  State<DependencyInjection> createState() => _DependencyInjectionState();
}

class _DependencyInjectionState extends State<DependencyInjection> {
  late final SdkViewModel sdkViewModel;

  @override
  void initState() {
    super.initState();
    sdkViewModel = SdkViewModel(factory: const SdkFactory());
  }

  @override
  void dispose() {
    sdkViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DependencyInjectionScope(
      sdkViewModel: sdkViewModel,
      child: widget.child,
    );
  }
}

class _DependencyInjectionScope extends InheritedWidget {
  const _DependencyInjectionScope({
    required this.sdkViewModel,
    required super.child,
  });

  final SdkViewModel sdkViewModel;

  @override
  bool updateShouldNotify(_DependencyInjectionScope old) => false;
}
