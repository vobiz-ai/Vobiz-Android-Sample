import 'package:flutter_test/flutter_test.dart';
import 'package:vobiz_demo/phone/numbers.dart';

void main() {
  group('toE164', () {
    test('keeps numbers that already have a +', () {
      expect(toE164('+919876543210'), '+919876543210');
      expect(toE164('+1 (415) 555-0100'), '+14155550100');
    });

    test('adds the default country code to ten digits', () {
      expect(toE164('9876543210'), '+919876543210');
      expect(toE164('98765 43210', countryCode: '44'), '+449876543210');
    });

    test('drops a leading 0 before adding the country code', () {
      expect(toE164('09876543210'), '+919876543210');
    });

    test('reads other lengths as including the country code', () {
      expect(toE164('919876543210'), '+919876543210');
    });

    test('refuses what is not a phone number', () {
      expect(toE164(''), isNull);
      expect(toE164('alice'), isNull);
      expect(toE164('12345'), isNull);
      expect(toE164('+1234567890123456'), isNull);
    });
  });

  group('displayParty', () {
    test('strips the SIP scheme and domain', () {
      expect(displayParty('sip:+919876543210@registrar.vobiz.ai'), '+919876543210');
      expect(displayParty('"Alice" <sip:alice@registrar.vobiz.ai>'), 'alice');
      expect(displayParty('+919876543210'), '+919876543210');
    });
  });

  group('callerFromHeaders', () {
    test('reads the real caller the sample server sends (X-VH-CallerX-VH)', () {
      expect(callerFromHeaders(<String, String>{'X-VH-CallerX-VH': '919876543210'}), '+919876543210');
    });

    test('ignores the header name case and a plain X-VH-Caller', () {
      expect(callerFromHeaders(<String, String>{'x-vh-callerx-vh': '+91 98765 43210'}), '+919876543210');
      expect(callerFromHeaders(<String, String>{'X-VH-Caller': '919876543210'}), '+919876543210');
    });

    test('is null without a usable header', () {
      expect(callerFromHeaders(const <String, String>{}), isNull);
      expect(callerFromHeaders(<String, String>{'X-VH-Reference': '919876543210'}), isNull);
      expect(callerFromHeaders(<String, String>{'X-VH-CallerX-VH': 'anonymous'}), isNull);
      expect(callerFromHeaders(<String, String>{'X-VH-Caller-ID': '919876543210'}), isNull);
    });
  });
}
