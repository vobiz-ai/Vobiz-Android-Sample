import 'package:flutter/foundation.dart';
import 'package:vobiz_webrtc/vobiz_webrtc.dart';

/// Build-time settings, passed with `--dart-define`. Nothing secret is built
/// into the app: the Vobiz Auth Token stays on the sample server.
class AppConfig {
  const AppConfig._();

  /// The sample server (Vobiz-RTC-demo). The default is the Android
  /// emulator's address for the computer it runs on.
  static const String backendUrl = String.fromEnvironment(
    'VOBIZ_BACKEND_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// The server's APP_KEY, sent as `X-App-Key` to its /token,
  /// /push/devices and /calls/transfer routes.
  ///
  /// It only keeps strangers off a demo server: anything built into an app
  /// can be read out of it. In production those routes sit behind your own
  /// user sign-in instead.
  static const String appKey = String.fromEnvironment('VOBIZ_APP_KEY');

  /// The country code added to numbers dialled without one.
  static const String defaultCountryCode = String.fromEnvironment(
    'VOBIZ_DEFAULT_COUNTRY_CODE',
    defaultValue: '91',
  );

  /// Builds the one [VobizClient] the app uses.
  static VobizClient createClient() => VobizClient(
        config: SdkConfig(
          // Only the legacy call-control methods would use this; the sample
          // calls its server through BackendApi instead.
          backendUrl: backendUrl,
          autoReconnect: true,
          debug: kDebugMode,
        ),
      );
}
