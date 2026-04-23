import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/logger.dart';

class BackendService {
  // Override with:
  // flutter run --dart-define=VOBIZ_BACKEND_URL=http://127.0.0.1:3000
  static const String _configuredBaseUrl = String.fromEnvironment(
    'VOBIZ_BACKEND_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );
  static const Duration timeout = Duration(seconds: 10);

  static String get baseUrl => _configuredBaseUrl.endsWith('/')
      ? _configuredBaseUrl.substring(0, _configuredBaseUrl.length - 1)
      : _configuredBaseUrl;

  static Future<Map<String, dynamic>?> getPendingCall() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/pending-call'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      Log.warn('Backend', 'getPendingCall failed: $e');
    }
    return null;
  }

  static Future<void> answerInbound() async {
    try {
      await http.post(Uri.parse('$baseUrl/answer-inbound')).timeout(timeout);
    } catch (e) {
      Log.warn('Backend', 'answerInbound failed: $e');
    }
  }

  static Future<void> holdCall() async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/hold-start'))
          .timeout(timeout);
      Log.info('Backend', 'holdCall: ${response.statusCode}');
    } catch (e) {
      Log.warn('Backend', 'holdCall failed (non-fatal): $e');
    }
  }

  static Future<void> resumeCall() async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/resume'))
          .timeout(timeout);
      Log.info('Backend', 'resumeCall: ${response.statusCode}');
    } catch (e) {
      Log.warn('Backend', 'resumeCall failed (non-fatal): $e');
    }
  }

  static Future<void> addCall(String to) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/add-call'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"to": to}),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception(
        'Add call failed: HTTP ${response.statusCode} - ${response.body}',
      );
    }
  }

  static Future<void> startSecondCall(String to) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/second-call'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"to": to}),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception(
        'Second call failed: HTTP ${response.statusCode} - ${response.body}',
      );
    }
  }

  static Future<void> swapCalls() async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/swap-calls'))
          .timeout(timeout);
      Log.info('Backend', 'swapCalls: ${response.statusCode}');
    } catch (e) {
      Log.warn('Backend', 'swapCalls failed: $e');
    }
  }

  static Future<void> mergeCalls() async {
    final response = await http
        .post(Uri.parse('$baseUrl/merge-calls'))
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception(
        'Merge failed: HTTP ${response.statusCode} - ${response.body}',
      );
    }
  }

  static Future<void> endSecondCall() async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/end-second-call'))
          .timeout(timeout);
      Log.info('Backend', 'endSecondCall: ${response.statusCode}');
    } catch (e) {
      Log.warn('Backend', 'endSecondCall failed: $e');
    }
  }

  static Future<void> removeAddedCall() async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/remove-added-call'))
          .timeout(timeout);
      Log.info('Backend', 'removeAddedCall: ${response.statusCode}');
    } catch (e) {
      Log.warn('Backend', 'removeAddedCall failed (non-fatal): $e');
    }
  }

  static Future<void> warmTransferStart(String to) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/warm-transfer/start'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"to": to}),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception(
        'Warm transfer failed: HTTP ${response.statusCode} - ${response.body}',
      );
    }
  }

  static Future<void> transferCall(String to) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/transfer'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"to": to}),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception(
        'Transfer failed: HTTP ${response.statusCode} - ${response.body}',
      );
    }
  }

  static Future<void> makeCall(String phoneNumber) async {
    try {
      final url = Uri.parse('$baseUrl/call');

      Log.info('Backend', 'Initiating call to: $phoneNumber');
      Log.info('Backend', 'URL: $url');

      final response = await http
          .post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"to": phoneNumber}),
      )
          .timeout(timeout, onTimeout: () {
        throw TimeoutException(
          'Backend request timed out after ${timeout.inSeconds}s',
          timeout,
        );
      });

      Log.info('Backend', 'Response status: ${response.statusCode}');
      Log.info('Backend', 'Response body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception(
          'Backend error: HTTP ${response.statusCode} - ${response.body}',
        );
      }

      Log.info('Backend', 'Call request successful');
    } on TimeoutException catch (e) {
      Log.error('Backend', 'Timeout: ${e.message}');
      rethrow;
    } catch (e) {
      Log.error('Backend', 'Error calling backend: $e');
      if (e.toString().contains('Cleartext HTTP traffic')) {
        throw Exception(
          'Backend HTTP traffic is blocked on this device. '
          'Use HTTPS or enable local cleartext traffic for the app.',
        );
      }
      rethrow;
    }
  }
}
