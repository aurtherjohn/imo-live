import 'package:flutter/foundation.dart';

/// A calling country: an ISO 3166-1 alpha-2 code, an English short name and an
/// ITU-T E.164 dial code.
///
/// ### Why this is hand-rolled rather than a package
///
/// The obvious move is `country_picker` or `fl_country_code_picker`. Both are
/// viable, but each pulls a dependency tree (and, for `fl_country_code_picker`,
/// a second one) into a build that is expensive to re-resolve here — a cold
/// Android release build on this machine measured ~48 minutes against a 5.6 GiB
/// transient requirement, on a disk with under 3 GB free.
///
/// The data itself is ~250 short rows that never change. Keeping it in-tree
/// means the picker works offline, adds no native code to the APK, cannot be
/// broken by a transitive version bump, and costs about as much to read as the
/// dependency declaration would have.
@immutable
class Country {
  const Country({
    required this.isoCode,
    required this.name,
    required this.dialCode,
  });

  /// ISO 3166-1 alpha-2, upper case — `BD`, `US`, `GB`.
  final String isoCode;

  /// English short name, as shown in the picker.
  final String name;

  /// ITU-T E.164 country calling code, **digits only** — no leading `+`.
  ///
  /// The `+` is deliberately not stored: it is a display affordance, not part
  /// of the number. The full E.164 value is built as `'+$dialCode$national'`
  /// and the digits-only form is what every index and comparison uses.
  final String dialCode;

  /// The regional-indicator flag for [isoCode], e.g. `🇧🇩`.
  ///
  /// Derived, never stored — see [flagEmoji]. That is what keeps this file free
  /// of image assets and of a 250-entry emoji table.
  String get flag => flagEmoji(isoCode);

  /// `+880`, for display.
  String get dial => '+$dialCode';

  /// `🇧🇩 Bangladesh` — the label the picker row shows.
  String get label => '$flag  $name';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Country && other.isoCode == isoCode);

  @override
  int get hashCode => isoCode.hashCode;

  @override
  String toString() => '$name ($dial)';
}

/// Builds the flag emoji for a two-letter country code.
///
/// A flag emoji is not a character with its own code point — it is the two
/// *regional indicator symbols* for the country's letters, which the platform
/// font ligates into a flag. `B` is `U+0042` and `🇧` is `U+1F1E7`; the offset
/// between them is constant, so the whole flag is two additions.
///
/// Returns an empty string for anything that is not two ASCII letters, so a
/// malformed row degrades to a missing flag rather than a run of tofu.
String flagEmoji(String isoCode) {
  final String code = isoCode.trim().toUpperCase();
  if (code.length != 2) return '';
  const int indicatorA = 0x1F1E6; // REGIONAL INDICATOR SYMBOL LETTER A
  const int letterA = 0x41; // 'A'
  final int first = code.codeUnitAt(0) - letterA;
  final int second = code.codeUnitAt(1) - letterA;
  if (first < 0 || first > 25 || second < 0 || second > 25) return '';
  return String.fromCharCodes(<int>[indicatorA + first, indicatorA + second]);
}

/// The calling-code table, and the lookups built on it.
class Countries {
  const Countries._();

  /// The country pre-selected on the phone screen.
  ///
  /// Bangladesh, because that is where this app's users are and where the
  /// number they are about to type will almost always be from. Picking it in
  /// advance saves the most common case a tap through the sheet.
  static const String defaultIsoCode = 'BD';

  /// Every country, ordered by English name.
  static final List<Country> all = _parse();

  static List<Country> _parse() {
    final List<Country> parsed = <Country>[];
    for (final String line in _raw.split('\n')) {
      final String row = line.trim();
      if (row.isEmpty || row.startsWith('#')) continue;
      final List<String> parts = row.split('|');
      if (parts.length != 3) continue;
      parsed.add(Country(
        isoCode: parts[0],
        name: parts[1],
        dialCode: parts[2],
      ));
    }
    parsed.sort((Country a, Country b) => a.name.compareTo(b.name));
    return List<Country>.unmodifiable(parsed);
  }

  /// The country [defaultIsoCode] names, or the first row if that is missing.
  static Country get defaultCountry => byIso(defaultIsoCode) ?? all.first;

  static Country? byIso(String isoCode) {
    final String code = isoCode.trim().toUpperCase();
    for (final Country country in all) {
      if (country.isoCode == code) return country;
    }
    return null;
  }

  /// Filters by name, ISO code or dial code, best matches first.
  ///
  /// Three ways in, because all three are natural things to type: `bang` (name
  /// prefix), `bd` (the code, exact) and `880` (the dial code). Prefix matches
  /// are returned before interior matches so typing `ind` surfaces India before
  /// Trinidad and Tobago.
  static List<Country> search(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return all;

    // Only treat the query as a dial-code search when it has digits; otherwise
    // every single-letter query would match half the table on `contains`.
    final String digits = q.replaceAll(RegExp(r'[^0-9]'), '');

    final List<Country> prefix = <Country>[];
    final List<Country> interior = <Country>[];

    for (final Country country in all) {
      final String name = country.name.toLowerCase();
      final String iso = country.isoCode.toLowerCase();
      final bool dialPrefix =
          digits.isNotEmpty && country.dialCode.startsWith(digits);

      if (name.startsWith(q) || iso == q || dialPrefix) {
        prefix.add(country);
      } else if (name.contains(q) || (digits.isNotEmpty && country.dialCode.contains(digits))) {
        interior.add(country);
      }
    }
    return <Country>[...prefix, ...interior];
  }

  /// `ISO|Name|DialCode`, one per line.
  ///
  /// Kept as a string rather than a list of constructor calls because it is
  /// read far more often than it is written, and one aligned row per country is
  /// the form in which a wrong dial code is actually visible.
  ///
  /// Names follow the app's naming for the special administrative regions:
  /// `Hong Kong SAR China`, `Macao SAR China`, `Taiwan, China`.
  static const String _raw = '''
AF|Afghanistan|93
AL|Albania|355
DZ|Algeria|213
AS|American Samoa|1
AD|Andorra|376
AO|Angola|244
AI|Anguilla|1
AG|Antigua and Barbuda|1
AR|Argentina|54
AM|Armenia|374
AW|Aruba|297
AU|Australia|61
AT|Austria|43
AZ|Azerbaijan|994
BS|Bahamas|1
BH|Bahrain|973
BD|Bangladesh|880
BB|Barbados|1
BY|Belarus|375
BE|Belgium|32
BZ|Belize|501
BJ|Benin|229
BM|Bermuda|1
BT|Bhutan|975
BO|Bolivia|591
BA|Bosnia and Herzegovina|387
BW|Botswana|267
BR|Brazil|55
IO|British Indian Ocean Territory|246
VG|British Virgin Islands|1
BN|Brunei|673
BG|Bulgaria|359
BF|Burkina Faso|226
BI|Burundi|257
KH|Cambodia|855
CM|Cameroon|237
CA|Canada|1
CV|Cape Verde|238
BQ|Caribbean Netherlands|599
KY|Cayman Islands|1
CF|Central African Republic|236
TD|Chad|235
CL|Chile|56
CN|China|86
CX|Christmas Island|61
CC|Cocos (Keeling) Islands|61
CO|Colombia|57
KM|Comoros|269
CG|Congo - Brazzaville|242
CD|Congo - Kinshasa|243
CK|Cook Islands|682
CR|Costa Rica|506
CI|Cote d'Ivoire|225
HR|Croatia|385
CU|Cuba|53
CW|Curacao|599
CY|Cyprus|357
CZ|Czechia|420
DK|Denmark|45
DJ|Djibouti|253
DM|Dominica|1
DO|Dominican Republic|1
EC|Ecuador|593
EG|Egypt|20
SV|El Salvador|503
GQ|Equatorial Guinea|240
ER|Eritrea|291
EE|Estonia|372
SZ|Eswatini|268
ET|Ethiopia|251
FK|Falkland Islands|500
FO|Faroe Islands|298
FJ|Fiji|679
FI|Finland|358
FR|France|33
GF|French Guiana|594
PF|French Polynesia|689
GA|Gabon|241
GM|Gambia|220
GE|Georgia|995
DE|Germany|49
GH|Ghana|233
GI|Gibraltar|350
GR|Greece|30
GL|Greenland|299
GD|Grenada|1
GP|Guadeloupe|590
GU|Guam|1
GT|Guatemala|502
GG|Guernsey|44
GN|Guinea|224
GW|Guinea-Bissau|245
GY|Guyana|592
HT|Haiti|509
HN|Honduras|504
HK|Hong Kong SAR China|852
HU|Hungary|36
IS|Iceland|354
IN|India|91
ID|Indonesia|62
IR|Iran|98
IQ|Iraq|964
IE|Ireland|353
IM|Isle of Man|44
IL|Israel|972
IT|Italy|39
JM|Jamaica|1
JP|Japan|81
JE|Jersey|44
JO|Jordan|962
KZ|Kazakhstan|7
KE|Kenya|254
KI|Kiribati|686
XK|Kosovo|383
KW|Kuwait|965
KG|Kyrgyzstan|996
LA|Laos|856
LV|Latvia|371
LB|Lebanon|961
LS|Lesotho|266
LR|Liberia|231
LY|Libya|218
LI|Liechtenstein|423
LT|Lithuania|370
LU|Luxembourg|352
MO|Macao SAR China|853
MG|Madagascar|261
MW|Malawi|265
MY|Malaysia|60
MV|Maldives|960
ML|Mali|223
MT|Malta|356
MH|Marshall Islands|692
MQ|Martinique|596
MR|Mauritania|222
MU|Mauritius|230
YT|Mayotte|262
MX|Mexico|52
FM|Micronesia|691
MD|Moldova|373
MC|Monaco|377
MN|Mongolia|976
ME|Montenegro|382
MS|Montserrat|1
MA|Morocco|212
MZ|Mozambique|258
MM|Myanmar|95
NA|Namibia|264
NR|Nauru|674
NP|Nepal|977
NL|Netherlands|31
NC|New Caledonia|687
NZ|New Zealand|64
NI|Nicaragua|505
NE|Niger|227
NG|Nigeria|234
NU|Niue|683
NF|Norfolk Island|672
KP|North Korea|850
MK|North Macedonia|389
MP|Northern Mariana Islands|1
NO|Norway|47
OM|Oman|968
PK|Pakistan|92
PW|Palau|680
PS|Palestine|970
PA|Panama|507
PG|Papua New Guinea|675
PY|Paraguay|595
PE|Peru|51
PH|Philippines|63
PL|Poland|48
PT|Portugal|351
PR|Puerto Rico|1
QA|Qatar|974
RE|Reunion|262
RO|Romania|40
RU|Russia|7
RW|Rwanda|250
WS|Samoa|685
SM|San Marino|378
ST|Sao Tome and Principe|239
SA|Saudi Arabia|966
SN|Senegal|221
RS|Serbia|381
SC|Seychelles|248
SL|Sierra Leone|232
SG|Singapore|65
SX|Sint Maarten|1
SK|Slovakia|421
SI|Slovenia|386
SB|Solomon Islands|677
SO|Somalia|252
ZA|South Africa|27
KR|South Korea|82
SS|South Sudan|211
ES|Spain|34
LK|Sri Lanka|94
BL|St. Barthelemy|590
SH|St. Helena|290
KN|St. Kitts and Nevis|1
LC|St. Lucia|1
MF|St. Martin|590
PM|St. Pierre and Miquelon|508
VC|St. Vincent and Grenadines|1
SD|Sudan|249
SR|Suriname|597
SJ|Svalbard and Jan Mayen|47
SE|Sweden|46
CH|Switzerland|41
SY|Syria|963
TW|Taiwan, China|886
TJ|Tajikistan|992
TZ|Tanzania|255
TH|Thailand|66
TL|Timor-Leste|670
TG|Togo|228
TK|Tokelau|690
TO|Tonga|676
TT|Trinidad and Tobago|1
TN|Tunisia|216
TR|Turkiye|90
TM|Turkmenistan|993
TC|Turks and Caicos Islands|1
TV|Tuvalu|688
UG|Uganda|256
UA|Ukraine|380
AE|United Arab Emirates|971
GB|United Kingdom|44
US|United States|1
UY|Uruguay|598
UZ|Uzbekistan|998
VU|Vanuatu|678
VA|Vatican City|39
VE|Venezuela|58
VN|Vietnam|84
WF|Wallis and Futuna|681
EH|Western Sahara|212
YE|Yemen|967
ZM|Zambia|260
ZW|Zimbabwe|263
''';
}
