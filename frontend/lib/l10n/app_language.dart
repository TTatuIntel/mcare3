import 'package:flutter/material.dart';

/// Supported languages across East Africa and neighbouring regions.
class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.englishName,
    required this.nativeName,
    required this.region,
  });

  final String code;
  final String englishName;
  final String nativeName;
  final String region;

  Locale get locale => Locale(code);

  String get displayLabel => '$nativeName · $englishName';

  static const defaultCode = 'en';

  static const all = <AppLanguage>[
    AppLanguage(
      code: 'en',
      englishName: 'English',
      nativeName: 'English',
      region: 'East Africa (widely used)',
    ),
    AppLanguage(
      code: 'sw',
      englishName: 'Swahili',
      nativeName: 'Kiswahili',
      region: 'Kenya · Tanzania · Uganda · Rwanda',
    ),
    AppLanguage(
      code: 'am',
      englishName: 'Amharic',
      nativeName: 'አማርኛ',
      region: 'Ethiopia',
    ),
    AppLanguage(
      code: 'om',
      englishName: 'Oromo',
      nativeName: 'Afaan Oromoo',
      region: 'Ethiopia',
    ),
    AppLanguage(
      code: 'ti',
      englishName: 'Tigrinya',
      nativeName: 'ትግርኛ',
      region: 'Ethiopia · Eritrea',
    ),
    AppLanguage(
      code: 'so',
      englishName: 'Somali',
      nativeName: 'Soomaali',
      region: 'Somalia · Kenya · Ethiopia',
    ),
    AppLanguage(
      code: 'ar',
      englishName: 'Arabic',
      nativeName: 'العربية',
      region: 'Sudan · Somalia · Djibouti',
    ),
    AppLanguage(
      code: 'fr',
      englishName: 'French',
      nativeName: 'Français',
      region: 'Rwanda · Burundi · DRC',
    ),
    AppLanguage(
      code: 'rw',
      englishName: 'Kinyarwanda',
      nativeName: 'Ikinyarwanda',
      region: 'Rwanda',
    ),
    AppLanguage(
      code: 'rn',
      englishName: 'Kirundi',
      nativeName: 'Ikirundi',
      region: 'Burundi',
    ),
    AppLanguage(
      code: 'lg',
      englishName: 'Luganda',
      nativeName: 'Luganda',
      region: 'Uganda',
    ),
    AppLanguage(
      code: 'ln',
      englishName: 'Lingala',
      nativeName: 'Lingála',
      region: 'DRC · Congo',
    ),
    AppLanguage(
      code: 'ny',
      englishName: 'Chichewa',
      nativeName: 'Chichewa',
      region: 'Malawi · Zambia',
    ),
    AppLanguage(
      code: 'zu',
      englishName: 'Zulu',
      nativeName: 'isiZulu',
      region: 'Southern Africa',
    ),
  ];

  static AppLanguage byCode(String? code) {
    if (code == null || code.isEmpty) return all.first;
    final normalized = _normalizeLegacyCode(code);
    return all.firstWhere(
      (l) => l.code == normalized,
      orElse: () => all.first,
    );
  }

  static String _normalizeLegacyCode(String raw) {
    return switch (raw.trim()) {
      'English' => 'en',
      'Swahili' => 'sw',
      'Kiswahili' => 'sw',
      _ => raw.length == 2 ? raw : 'en',
    };
  }

  static List<String> get regionGroups {
    final seen = <String>{};
    final groups = <String>[];
    for (final lang in all) {
      if (seen.add(lang.region)) groups.add(lang.region);
    }
    return groups;
  }

  static List<AppLanguage> forRegion(String region) =>
      all.where((l) => l.region == region).toList();
}
