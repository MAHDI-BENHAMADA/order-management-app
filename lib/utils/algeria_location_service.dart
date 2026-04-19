import 'dart:convert';

import 'package:flutter/services.dart';

class AlgeriaLocationService {
  static bool _loaded = false;

  static final List<String> _wilayas = <String>[];
  static final Map<String, List<String>> _wilayaToCommunes =
      <String, List<String>>{};

  static final Map<String, String> _normalizedWilayaLookup = <String, String>{};
  static final Map<String, String> _normalizedCommuneLookup =
      <String, String>{};

  static Future<void> ensureLoaded() async {
    if (_loaded) return;

    final raw = await rootBundle.loadString('algeria_cities.json');
    final List<dynamic> parsed = jsonDecode(raw) as List<dynamic>;

    final wilayaSet = <String>{};
    final communesByWilaya = <String, Set<String>>{};

    for (final item in parsed) {
      final map = item as Map<String, dynamic>;

      final wilayaArabic = (map['wilaya_name'] ?? '').toString().trim();
      final wilayaAscii = (map['wilaya_name_ascii'] ?? '').toString().trim();
      final communeArabic = (map['commune_name'] ?? '').toString().trim();
      final communeAscii = (map['commune_name_ascii'] ?? '').toString().trim();

      if (wilayaArabic.isEmpty || communeArabic.isEmpty) continue;

      wilayaSet.add(wilayaArabic);
      communesByWilaya.putIfAbsent(wilayaArabic, () => <String>{});
      communesByWilaya[wilayaArabic]!.add(communeArabic);

      _normalizedWilayaLookup[_normalize(wilayaArabic)] = wilayaArabic;
      if (wilayaAscii.isNotEmpty) {
        _normalizedWilayaLookup[_normalize(wilayaAscii)] = wilayaArabic;
      }

      _normalizedCommuneLookup[_normalize(communeArabic)] = communeArabic;
      if (communeAscii.isNotEmpty) {
        _normalizedCommuneLookup[_normalize(communeAscii)] = communeArabic;
      }
    }

    _wilayas
      ..clear()
      ..addAll(wilayaSet)
      ..sort();

    _wilayaToCommunes.clear();
    for (final entry in communesByWilaya.entries) {
      final communes = entry.value.toList()..sort();
      _wilayaToCommunes[entry.key] = communes;
    }

    _loaded = true;
  }

  static List<String> getWilayas() {
    return List<String>.unmodifiable(_wilayas);
  }

  static List<String> getCommunesForWilaya(String wilaya) {
    final normalizedWilaya = normalizeWilaya(wilaya);
    if (normalizedWilaya == null) return const <String>[];

    return List<String>.unmodifiable(
      _wilayaToCommunes[normalizedWilaya] ?? const <String>[],
    );
  }

  static String? normalizeWilaya(String value) {
    if (value.trim().isEmpty) return null;
    return _normalizedWilayaLookup[_normalize(value)];
  }

  static String? normalizeCommune(String wilaya, String commune) {
    if (commune.trim().isEmpty) return null;

    final normalizedWilaya = normalizeWilaya(wilaya);
    if (normalizedWilaya == null) return null;

    final communes = _wilayaToCommunes[normalizedWilaya] ?? const <String>[];
    final normalizedTarget = _normalize(commune);

    for (final item in communes) {
      if (_normalize(item) == normalizedTarget) {
        return item;
      }
    }

    final fromAscii = _normalizedCommuneLookup[normalizedTarget];
    if (fromAscii != null && communes.contains(fromAscii)) {
      return fromAscii;
    }

    return null;
  }

  static bool isValidCommuneForWilaya(String wilaya, String commune) {
    final normalizedWilaya = normalizeWilaya(wilaya);
    if (normalizedWilaya == null) return false;

    final normalizedCommune = normalizeCommune(normalizedWilaya, commune);
    if (normalizedCommune == null) return false;

    return (_wilayaToCommunes[normalizedWilaya] ?? const <String>[]).contains(
      normalizedCommune,
    );
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('ـ', '');
  }
}
