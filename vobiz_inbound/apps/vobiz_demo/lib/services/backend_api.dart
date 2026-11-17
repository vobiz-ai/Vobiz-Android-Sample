import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vobiz_webrtc/vobiz_webrtc.dart';

/// The sample server's routes for the app (Vobiz-RTC-demo/server.js). Each
/// request carries the app key; the server adds the account's credentials.
class BackendApi {
  BackendApi({required this.baseUrl, required this.appKey, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String appKey;
  final http.Client _http;

  bool get hasAppKey => appKey.isNotEmpty;

  Map<String, String> get _headers => <String, String>{'X-App-Key': appKey};

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  /// Access tokens for [identity], from `POST /token?sub=<identity>`. The
  /// SDK asks again before each token expires, and when the registrar
  /// refuses one.
  VobizAccessTokenProvider tokenProvider(String identity) => VobizBackendAccessTokenProvider(
        url: _uri('/token', <String, String>{'sub': identity}),
        headers: () => _headers,
        httpClient: _http,
      ).call;

  /// Registers this phone with Vobiz push through the server
  /// (`POST /push/devices/register`), which adds the account's credentials.
  /// The body is exactly what Vobiz expects.
  VobizPushDevices pushDevices() => VobizPushDevices(
        baseUrl: Uri.parse(baseUrl),
        pathPrefix: '/push/devices',
        authHeaders: () => _headers,
        httpClient: _http,
      );

  /// Sends the other party of the call [callUuid] to [to], a phone number or
  /// a SIP user name (`POST /calls/transfer`).
  Future<void> transfer({required String callUuid, required String to}) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            _uri('/calls/transfer'),
            headers: <String, String>{..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode(<String, String>{'call_uuid': callUuid, 'to': to}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw BackendException('Could not reach the server: $e');
    }
    if (response.statusCode >= 400) throw BackendException(_reason(response));
  }

  static String _reason(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is String) return body['error'] as String;
    } catch (_) {}
    return 'The server answered ${response.statusCode}';
  }
}

class BackendException implements Exception {
  const BackendException(this.message);
  final String message;

  @override
  String toString() => message;
}
