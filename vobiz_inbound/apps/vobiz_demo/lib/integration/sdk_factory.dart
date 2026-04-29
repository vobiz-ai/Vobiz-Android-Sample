import 'package:vobiz_webrtc/vobiz_webrtc.dart';

class SdkFactory {
  const SdkFactory();

  static const _backendUrl = String.fromEnvironment(
    'VOBIZ_BACKEND_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const _answerUrl = String.fromEnvironment(
    'VOBIZ_ANSWER_URL',
    defaultValue: '',
  );

  static String get backendUrl => _backendUrl;

  VobizClient createClient() {
    return VobizClient(
      config: SdkConfig(
        wsUrl: 'wss://registrar.vobiz.ai:5063/',
        sipServer: 'registrar.vobiz.ai',
        backendUrl: _backendUrl,
        answerUrl: _answerUrl.isEmpty ? null : _answerUrl,
        autoReconnect: true,
        debug: true,
      ),
    );
  }
}
