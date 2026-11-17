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
}
