/// Turns what the user typed into an E.164 number (`+919876543210`), or null
/// when it is not a phone number.
///
/// `+` numbers are kept; ten digits get [countryCode]; eleven digits starting
/// with 0 lose the 0 and get [countryCode]; any other 8 to 15 digits are read
/// as already including a country code.
String? toE164(String input, {String countryCode = '91'}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty || !RegExp(r'^\+?[\d\s().-]+$').hasMatch(trimmed)) return null;
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  final String number;
  if (trimmed.startsWith('+')) {
    number = '+$digits';
  } else if (digits.length == 10) {
    number = '+$countryCode$digits';
  } else if (digits.length == 11 && digits.startsWith('0')) {
    number = '+$countryCode${digits.substring(1)}';
  } else {
    number = '+$digits';
  }
  return RegExp(r'^\+\d{8,15}$').hasMatch(number) ? number : null;
}

/// Who a call is with, for the screen: `sip:+9198...@registrar.vobiz.ai` and
/// `"Name" <sip:alice@...>` become `+9198...` and `alice`.
String displayParty(String raw) {
  var value = raw.trim();
  final angle = RegExp(r'<([^>]+)>').firstMatch(value);
  if (angle != null) value = angle.group(1)!;
  value = value.replaceFirst(RegExp(r'^sips?:', caseSensitive: false), '');
  final at = value.indexOf('@');
  if (at > 0) value = value.substring(0, at);
  return value;
}
