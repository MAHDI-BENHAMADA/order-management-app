import 'dart:convert';
import 'package:flutter/services.dart';
import '../services/ecotrack_service.dart';

class AlgeriaLocationService {
  static bool _loaded = false;

  static final List<String> _wilayas = <String>[];
  static final Map<String, int> _wilayaNameToId = <String, int>{};
  static final Map<String, List<String>> _wilayaToCommunes =
      <String, List<String>>{};

  // Fallback hardcoded wilayas in case API fails
  // Fallback hardcoded wilayas in case API fails
  static const Map<String, int> _fallbackWilayaCodes = {
    '01. أدرار': 1,
    '02. الشلف': 2,
    '03. الأغواط': 3,
    '04. أم البواقي': 4,
    '05. باتنة': 5,
    '06. بجاية': 6,
    '07. بسكرة': 7,
    '08. بشار': 8,
    '09. البليدة': 9,
    '10. البويرة': 10,
    '11. تمنراست': 11,
    '12. تبسة': 12,
    '13. تلمسان': 13,
    '14. تيارت': 14,
    '15. تيزي وزو': 15,
    '16. الجزائر': 16,
    '17. الجلفة': 17,
    '18. جيجل': 18,
    '19. سطيف': 19,
    '20. سعيدة': 20,
    '21. سكيكدة': 21,
    '22. سيدي بلعباس': 22,
    '23. عنابة': 23,
    '24. قالمة': 24,
    '25. قسنطينة': 25,
    '26. المدية': 26,
    '27. مستغانم': 27,
    '28. المسيلة': 28,
    '29. معسكر': 29,
    '30. ورقلة': 30,
    '31. وهران': 31,
    '32. البيض': 32,
    '33. إليزي': 33,
    '34. برج بوعريريج': 34,
    '35. بومرداس': 35,
    '36. الطارف': 36,
    '37. تندوف': 37,
    '38. تيسمسيلت': 38,
    '39. الوادي': 39,
    '40. خنشلة': 40,
    '41. سوق أهراس': 41,
    '42. تيبازة': 42,
    '43. ميلة': 43,
    '44. عين الدفلى': 44,
    '45. النعامة': 45,
    '46. عين تموشنت': 46,
    '47. غرداية': 47,
    '48. غليزان': 48,
    '49. تميمون': 49,
    '50. برج باجي مختار': 50,
    '51. أولاد جلال': 51,
    '52. بني عباس': 52,
    '53. عين صالح': 53,
    '54. عين قزام': 54,
    '55. تقرت': 55,
    '56. جانت': 56,
    '57. المغير': 57,
    '58. المنيعة': 58,
  };

  static Future<void> ensureLoaded() async {
    if (_loaded) return;

    try {
      // Step 1: Fetch wilayas from EcoTrack API
      print('📍 Loading wilayas from EcoTrack API...');
      final wilayasData = await EcoTrackService.getWilayasFromApi();

      if (wilayasData.isEmpty) {
        print('⚠️ EcoTrack API returned no wilayas, using fallback');
        _loadFallbackData();
        return;
      }

      _wilayas.clear();
      _wilayaNameToId.clear();

      // Load wilayas from API response
      for (final wilaya in wilayasData) {
        final wilayaName = wilaya['wilaya_name'] ?? wilaya['nom'] ?? '';
        final wilayaId = wilaya['wilaya_id'] ?? wilaya['id'] ?? 0;

        if (wilayaName.isNotEmpty && wilayaId != 0) {
          final nameStr = wilayaName.toString().trim();
          _wilayaNameToId[nameStr] = wilayaId as int;
        }
      }

      print('📊 API returned ${_wilayaNameToId.length} wilayas');

      // Supplement with fallback: add any wilaya IDs that the API missed
      final apiIds = _wilayaNameToId.values.toSet();
      for (final entry in _fallbackWilayaCodes.entries) {
        if (!apiIds.contains(entry.value)) {
          print('➕ Adding missing wilaya from fallback: ${entry.key} (ID: ${entry.value})');
          _wilayaNameToId[entry.key] = entry.value;
        }
      }

      // Sort by wilaya ID numerically (01 → 58)
      final sortedEntries = _wilayaNameToId.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      _wilayas
        ..clear()
        ..addAll(sortedEntries.map((e) => e.key));

      print('✅ Total wilayas after merge: ${_wilayas.length}');

      // Step 2: Load communes from LOCAL JSON file (NO API CALLS = NO RATE LIMITING!)
      print('📚 Loading communes from local JSON file...');
      await _loadCommunesFromLocalJson();

      _loaded = true;
      print('✅ AlgeriaLocationService fully loaded');
    } catch (e) {
      print('❌ Error during location data loading: $e');
      _loadFallbackData();
    }
  }

  static Future<void> _loadCommunesFromLocalJson() async {
    try {
      final jsonString = await rootBundle.loadString('communes.json');
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

      _wilayaToCommunes.clear();

      // Parse the communes JSON
      for (final entry in jsonData.entries) {
        final commune = entry.value as Map<String, dynamic>;
        final communeName = commune['nom'] as String?;
        final wilayaId = commune['wilaya_id'] as int?;

        if (communeName != null && communeName.isNotEmpty && wilayaId != null) {
          // Find wilaya name by ID
          String? wilayaName;
          for (final entry in _wilayaNameToId.entries) {
            if (entry.value == wilayaId) {
              wilayaName = entry.key;
              break;
            }
          }

          if (wilayaName != null) {
            _wilayaToCommunes.putIfAbsent(wilayaName, () => <String>[]);
            if (!_wilayaToCommunes[wilayaName]!.contains(communeName)) {
              _wilayaToCommunes[wilayaName]!.add(communeName);
            }
          }
        }
      }

      // Sort communes for each wilaya
      for (final communes in _wilayaToCommunes.values) {
        communes.sort();
      }

      final totalCommunes = _wilayaToCommunes.values.fold<int>(
        0,
        (sum, list) => sum + list.length,
      );
      print('✅ Loaded $totalCommunes communes from local JSON');
    } catch (e) {
      print('❌ Error loading communes from JSON: $e');
    }
  }

  static void _loadFallbackData() {
    _wilayas.clear();
    _wilayaNameToId.clear();

    for (final entry in _fallbackWilayaCodes.entries) {
      _wilayas.add(entry.key);
      _wilayaNameToId[entry.key] = entry.value;
    }

    _wilayas.sort();
    _loaded = true;
    print('✅ Using fallback wilayas (${_wilayas.length} total)');
  }

  static List<String> getWilayas() {
    return List<String>.unmodifiable(_wilayas);
  }

  // Get wilaya ID by name (used for EcoTrack API calls)
  static int? getWilayaId(String wilaya) {
    if (!_loaded) return null;

    final trimmed = wilaya.trim();
    if (trimmed.isEmpty) return null;

    // Try to extract ID if it starts with digits (e.g. "16 - Alger" or "16")
    final idMatch = RegExp(r'^(\d+)').firstMatch(trimmed);
    if (idMatch != null) {
      final id = int.tryParse(idMatch.group(1)!);
      if (id != null) {
        // Find wilaya with this ID
        for (final entry in _wilayaNameToId.entries) {
          if (entry.value == id) return id;
        }
      }
    }

    // Try exact match first
    if (_wilayaNameToId.containsKey(trimmed)) {
      return _wilayaNameToId[trimmed];
    }

    // Try normalized match
    final normalized = _normalize(trimmed);
    for (final entry in _wilayaNameToId.entries) {
      if (_normalize(entry.key) == normalized) {
        return entry.value;
      }
    }

    return null;
  }

  static List<String> getCommunesForWilaya(String wilaya) {
    if (!_loaded) return const <String>[];

    final normalizedWilaya = normalizeWilaya(wilaya);
    if (normalizedWilaya == null) return const <String>[];

    // Try exact match first
    if (_wilayaToCommunes.containsKey(normalizedWilaya)) {
      return List<String>.unmodifiable(
        _wilayaToCommunes[normalizedWilaya] ?? const <String>[],
      );
    }

    return const <String>[];
  }

  static String? normalizeWilaya(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    // 1. Try to extract ID and match (handles "16 - Alger", "16 الجزائر", "16")
    final idMatch = RegExp(r'^(\d+)').firstMatch(trimmed);
    if (idMatch != null) {
      final id = int.tryParse(idMatch.group(1)!);
      if (id != null) {
        for (final entry in _wilayaNameToId.entries) {
          if (entry.value == id) return entry.key;
        }
      }
    }

    // 2. Try exact match
    if (_wilayas.contains(trimmed)) {
      return trimmed;
    }

    // 3. Try normalized match (ignoring spaces, case, etc)
    final normalized = _normalize(trimmed);
    for (final wilaya in _wilayas) {
      if (_normalize(wilaya) == normalized) {
        return wilaya;
      }
    }

    return null;
  }

  static String? normalizeCommune(String wilaya, String commune) {
    if (commune.trim().isEmpty) return null;

    final normalizedWilaya = normalizeWilaya(wilaya);
    if (normalizedWilaya == null) return null;

    final communes = _wilayaToCommunes[normalizedWilaya] ?? const <String>[];
    
    // Try exact match first
    if (communes.contains(commune)) {
      return commune;
    }

    // Try normalized match
    final normalized = _normalize(commune);
    for (final c in communes) {
      if (_normalize(c) == normalized) {
        return c;
      }
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
