import 'package:vobiz_webrtc/vobiz_webrtc.dart';

class SdkFactory {
  const SdkFactory();

  static const _backendUrl = String.fromEnvironment(
    'VOBIZ_BACKEND_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  VobizClient createClient() {
    return VobizClient(
      config: const SdkConfig(
        wsUrl: 'wss://registrar.vobiz.ai:5063/',
        sipServer: 'registrar.vobiz.ai',
        backendUrl: _backendUrl,
        autoReconnect: true,
        debug: true,
      ),
    );
  }
}
