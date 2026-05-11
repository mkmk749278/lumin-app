/// Country / dial-code reference data — used by [PhoneSignInPage]
/// (country chip + auto-detect) and [SignupPage] (country picker).
///
/// Three columns per entry:
///   * ISO 3166-1 alpha-2 code (``"SG"``)
///   * Dial code without leading ``+`` (``"65"``)
///   * Country display name in English (``"Singapore"``)
///
/// A flag emoji is derived from the ISO code via [flagFor] — Unicode
/// regional-indicator-letter trick, no asset needed.
///
/// Currency is *not* in this list — the SignupPage uses a separate
/// small ISO-3166→ISO-4217 mapping ([currencyForCountry]) because some
/// countries share a currency and the relationship isn't 1:1.
library;

import 'dart:ui' show Locale;

class CountryCode {
  const CountryCode(this.iso2, this.dial, this.name);

  /// ISO 3166-1 alpha-2 (uppercased).
  final String iso2;

  /// E.164 dial code, no leading "+".  Some entries share dial codes
  /// (NANP: ``US``, ``CA``, ``BS``, ...).
  final String dial;

  /// English country name (display only).
  final String name;

  /// Regional-indicator flag emoji — composed from the ISO code.  No
  /// asset / font dependency: every modern Android renders these via
  /// the system emoji font.
  String get flag => flagFor(iso2);
}

/// Convert an ISO 3166-1 alpha-2 code to its flag emoji using the
/// Unicode regional-indicator-letter trick.  Returns the world emoji
/// for blank / invalid input so the chip always renders something.
String flagFor(String? iso2) {
  if (iso2 == null || iso2.length != 2) return '\u{1F310}';
  final upper = iso2.toUpperCase();
  final a = upper.codeUnitAt(0);
  final b = upper.codeUnitAt(1);
  if (a < 0x41 || a > 0x5A || b < 0x41 || b > 0x5A) return '\u{1F310}';
  return String.fromCharCodes([
    0x1F1E6 + (a - 0x41),
    0x1F1E6 + (b - 0x41),
  ]);
}

/// Resolve a default country from the device locale.  Returns the
/// fallback when no region letter is present (``en`` without ``_US``).
CountryCode defaultCountryFromLocale(Locale locale, {String fallbackIso2 = 'US'}) {
  final region = locale.countryCode;
  if (region != null && region.length == 2) {
    final hit = lookupCountry(region);
    if (hit != null) return hit;
  }
  final fb = lookupCountry(fallbackIso2);
  return fb ?? const CountryCode('US', '1', 'United States');
}

/// Linear lookup — the table is ~250 entries; binary search would be
/// premature.  Returns null on unknown ISO codes.
CountryCode? lookupCountry(String iso2) {
  final upper = iso2.toUpperCase();
  for (final c in kCountryCodes) {
    if (c.iso2 == upper) return c;
  }
  return null;
}

/// Resolve a country from a phone E.164 prefix (leading ``+`` ignored).
/// Longest-match: ``+1242`` (Bahamas) wins over ``+1`` (US) on overlap.
/// Returns null when no entry's dial code prefixes the number.
CountryCode? countryForE164(String e164) {
  var s = e164.startsWith('+') ? e164.substring(1) : e164;
  // Sort by descending dial length so the first prefix-hit wins.
  final sorted = [...kCountryCodes]
    ..sort((a, b) => b.dial.length.compareTo(a.dial.length));
  for (final c in sorted) {
    if (s.startsWith(c.dial)) return c;
  }
  return null;
}

/// Best-effort currency hint from country.  Covers the common cases the
/// app will see across the first wave of beta; for missed regions the
/// user can change the currency picker manually.
String currencyForCountry(String? iso2) {
  if (iso2 == null) return 'USD';
  switch (iso2.toUpperCase()) {
    case 'GB':
      return 'GBP';
    case 'AU':
      return 'AUD';
    case 'NZ':
      return 'NZD';
    case 'CA':
      return 'CAD';
    case 'IN':
      return 'INR';
    case 'JP':
      return 'JPY';
    case 'CN':
      return 'CNY';
    case 'HK':
      return 'HKD';
    case 'TW':
      return 'TWD';
    case 'KR':
      return 'KRW';
    case 'SG':
      return 'SGD';
    case 'MY':
      return 'MYR';
    case 'ID':
      return 'IDR';
    case 'PH':
      return 'PHP';
    case 'TH':
      return 'THB';
    case 'VN':
      return 'VND';
    case 'AE':
      return 'AED';
    case 'SA':
      return 'SAR';
    case 'IL':
      return 'ILS';
    case 'EG':
      return 'EGP';
    case 'ZA':
      return 'ZAR';
    case 'BR':
      return 'BRL';
    case 'AR':
      return 'ARS';
    case 'MX':
      return 'MXN';
    case 'CL':
      return 'CLP';
    case 'CO':
      return 'COP';
    case 'TR':
      return 'TRY';
    case 'RU':
      return 'RUB';
    case 'CH':
      return 'CHF';
    case 'PL':
      return 'PLN';
    case 'SE':
      return 'SEK';
    case 'NO':
      return 'NOK';
    case 'DK':
      return 'DKK';
    case 'CZ':
      return 'CZK';
    // Eurozone — covers the major beta countries that share EUR.
    case 'DE':
    case 'FR':
    case 'IT':
    case 'ES':
    case 'NL':
    case 'BE':
    case 'AT':
    case 'IE':
    case 'PT':
    case 'GR':
    case 'FI':
    case 'LU':
    case 'SK':
    case 'SI':
    case 'EE':
    case 'LV':
    case 'LT':
    case 'CY':
    case 'MT':
      return 'EUR';
    default:
      return 'USD';
  }
}

/// The reference table.  Sorted by dial code then name for easy
/// scanning.  This list is intentionally hand-maintained — it changes
/// less than once a year and a package dependency for static data is
/// not worth the build-graph weight.
const List<CountryCode> kCountryCodes = [
  // +1 NANP
  CountryCode('US', '1', 'United States'),
  CountryCode('CA', '1', 'Canada'),
  // Western Europe
  CountryCode('GB', '44', 'United Kingdom'),
  CountryCode('IE', '353', 'Ireland'),
  CountryCode('FR', '33', 'France'),
  CountryCode('DE', '49', 'Germany'),
  CountryCode('ES', '34', 'Spain'),
  CountryCode('IT', '39', 'Italy'),
  CountryCode('PT', '351', 'Portugal'),
  CountryCode('NL', '31', 'Netherlands'),
  CountryCode('BE', '32', 'Belgium'),
  CountryCode('LU', '352', 'Luxembourg'),
  CountryCode('CH', '41', 'Switzerland'),
  CountryCode('AT', '43', 'Austria'),
  CountryCode('SE', '46', 'Sweden'),
  CountryCode('NO', '47', 'Norway'),
  CountryCode('DK', '45', 'Denmark'),
  CountryCode('FI', '358', 'Finland'),
  CountryCode('IS', '354', 'Iceland'),
  // Central / Eastern Europe
  CountryCode('PL', '48', 'Poland'),
  CountryCode('CZ', '420', 'Czech Republic'),
  CountryCode('SK', '421', 'Slovakia'),
  CountryCode('HU', '36', 'Hungary'),
  CountryCode('RO', '40', 'Romania'),
  CountryCode('BG', '359', 'Bulgaria'),
  CountryCode('GR', '30', 'Greece'),
  CountryCode('SI', '386', 'Slovenia'),
  CountryCode('HR', '385', 'Croatia'),
  CountryCode('RS', '381', 'Serbia'),
  CountryCode('EE', '372', 'Estonia'),
  CountryCode('LV', '371', 'Latvia'),
  CountryCode('LT', '370', 'Lithuania'),
  CountryCode('CY', '357', 'Cyprus'),
  CountryCode('MT', '356', 'Malta'),
  CountryCode('UA', '380', 'Ukraine'),
  CountryCode('BY', '375', 'Belarus'),
  CountryCode('MD', '373', 'Moldova'),
  CountryCode('RU', '7', 'Russia'),
  CountryCode('KZ', '7', 'Kazakhstan'),
  // Middle East
  CountryCode('TR', '90', 'Turkey'),
  CountryCode('IL', '972', 'Israel'),
  CountryCode('AE', '971', 'United Arab Emirates'),
  CountryCode('SA', '966', 'Saudi Arabia'),
  CountryCode('QA', '974', 'Qatar'),
  CountryCode('KW', '965', 'Kuwait'),
  CountryCode('BH', '973', 'Bahrain'),
  CountryCode('OM', '968', 'Oman'),
  CountryCode('JO', '962', 'Jordan'),
  CountryCode('LB', '961', 'Lebanon'),
  CountryCode('IQ', '964', 'Iraq'),
  CountryCode('IR', '98', 'Iran'),
  // South Asia
  CountryCode('IN', '91', 'India'),
  CountryCode('PK', '92', 'Pakistan'),
  CountryCode('BD', '880', 'Bangladesh'),
  CountryCode('LK', '94', 'Sri Lanka'),
  CountryCode('NP', '977', 'Nepal'),
  CountryCode('BT', '975', 'Bhutan'),
  CountryCode('MV', '960', 'Maldives'),
  CountryCode('AF', '93', 'Afghanistan'),
  // East / SE Asia
  CountryCode('CN', '86', 'China'),
  CountryCode('HK', '852', 'Hong Kong'),
  CountryCode('MO', '853', 'Macao'),
  CountryCode('TW', '886', 'Taiwan'),
  CountryCode('JP', '81', 'Japan'),
  CountryCode('KR', '82', 'South Korea'),
  CountryCode('KP', '850', 'North Korea'),
  CountryCode('MN', '976', 'Mongolia'),
  CountryCode('SG', '65', 'Singapore'),
  CountryCode('MY', '60', 'Malaysia'),
  CountryCode('TH', '66', 'Thailand'),
  CountryCode('VN', '84', 'Vietnam'),
  CountryCode('PH', '63', 'Philippines'),
  CountryCode('ID', '62', 'Indonesia'),
  CountryCode('KH', '855', 'Cambodia'),
  CountryCode('LA', '856', 'Laos'),
  CountryCode('MM', '95', 'Myanmar'),
  CountryCode('BN', '673', 'Brunei'),
  CountryCode('TL', '670', 'Timor-Leste'),
  // Oceania
  CountryCode('AU', '61', 'Australia'),
  CountryCode('NZ', '64', 'New Zealand'),
  CountryCode('FJ', '679', 'Fiji'),
  CountryCode('PG', '675', 'Papua New Guinea'),
  // Africa — common
  CountryCode('ZA', '27', 'South Africa'),
  CountryCode('NG', '234', 'Nigeria'),
  CountryCode('EG', '20', 'Egypt'),
  CountryCode('KE', '254', 'Kenya'),
  CountryCode('GH', '233', 'Ghana'),
  CountryCode('TZ', '255', 'Tanzania'),
  CountryCode('UG', '256', 'Uganda'),
  CountryCode('ET', '251', 'Ethiopia'),
  CountryCode('MA', '212', 'Morocco'),
  CountryCode('DZ', '213', 'Algeria'),
  CountryCode('TN', '216', 'Tunisia'),
  CountryCode('LY', '218', 'Libya'),
  CountryCode('SN', '221', 'Senegal'),
  CountryCode('CI', '225', 'Côte d\'Ivoire'),
  CountryCode('CM', '237', 'Cameroon'),
  CountryCode('ZW', '263', 'Zimbabwe'),
  CountryCode('ZM', '260', 'Zambia'),
  CountryCode('MZ', '258', 'Mozambique'),
  CountryCode('AO', '244', 'Angola'),
  CountryCode('NA', '264', 'Namibia'),
  CountryCode('BW', '267', 'Botswana'),
  CountryCode('MG', '261', 'Madagascar'),
  CountryCode('MU', '230', 'Mauritius'),
  CountryCode('RW', '250', 'Rwanda'),
  CountryCode('SD', '249', 'Sudan'),
  CountryCode('SO', '252', 'Somalia'),
  // Americas
  CountryCode('MX', '52', 'Mexico'),
  CountryCode('BR', '55', 'Brazil'),
  CountryCode('AR', '54', 'Argentina'),
  CountryCode('CL', '56', 'Chile'),
  CountryCode('CO', '57', 'Colombia'),
  CountryCode('PE', '51', 'Peru'),
  CountryCode('VE', '58', 'Venezuela'),
  CountryCode('EC', '593', 'Ecuador'),
  CountryCode('BO', '591', 'Bolivia'),
  CountryCode('PY', '595', 'Paraguay'),
  CountryCode('UY', '598', 'Uruguay'),
  CountryCode('CR', '506', 'Costa Rica'),
  CountryCode('PA', '507', 'Panama'),
  CountryCode('DO', '1809', 'Dominican Republic'),
  CountryCode('GT', '502', 'Guatemala'),
  CountryCode('SV', '503', 'El Salvador'),
  CountryCode('HN', '504', 'Honduras'),
  CountryCode('NI', '505', 'Nicaragua'),
  CountryCode('CU', '53', 'Cuba'),
  CountryCode('JM', '1876', 'Jamaica'),
  CountryCode('BS', '1242', 'Bahamas'),
  CountryCode('BB', '1246', 'Barbados'),
  CountryCode('TT', '1868', 'Trinidad and Tobago'),
  CountryCode('PR', '1787', 'Puerto Rico'),
];
